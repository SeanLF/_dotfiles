---
title: A passing test may be asserting nothing; mutate the fix and watch it fail before you believe it
date: 2026-07-25
category: test-failures
module: any test-guarded change
problem_type: test_failure
severity: high
applies_when:
  - You wrote a test alongside a fix and it passed first time
  - A test guards a tuned constant, threshold or timeout
  - A test asserts over a collection, map or parser output you did not print
  - You are about to claim in a commit message or PR that a change is "verified by tests"
tags:
  [testing, mutation-testing, verification, false-negatives, go, concurrency]
---

## The lesson

A test that passes proves nothing until you have seen it fail for the right reason.
Revert **only** the fix it guards, re-run, and confirm it fails **with its own message**.
If it passes, or fails with a panic from somewhere else, it is not guarding what you
think.

## What happened

Hardening a DNS daemon, four separate tests I wrote and believed in were hollow:

- **Asserted over an empty collection.** A test walked a parser's output map checking for
  invalid entries. It passed. The map was empty — the input never parsed. Printing what
  the parser actually returned exposed _two_ real bugs the test had been blind to.
- **Self-referential threshold.** A test for "a slow operation still completes" defined
  slow as `activationSettle / 4` — a fraction of the very constant it guarded. Mutating
  the constant mutated the test. It passed with the constant at **1 nanosecond** and at
  **5 minutes**. It only failed at exactly zero, so it tested "the timeout is non-zero".
- **Never ran its own subject.** The same test called `Stop()` before the goroutine under
  test was first scheduled, so its "slow callback" never executed at all.
- **Failed for the wrong reason.** Another failed on revert via
  `panic: deadlock: all goroutines in bubble are blocked`, which aborted the test binary
  and prevented later tests from running. Its crafted failure message was dead code.

Related, from the same session: two "experiments" proved nothing because `timeout` does
not exist on macOS (every run was `command not found`, reported as a pass), and container
output piped through `tail` buffers to nothing.

## Guidance

- Mutate one fix at a time. Reverting several at once tells you which _suite_ fails, not
  which assertion works.
- If the mutation will not compile (an unused variable, say), that is not a pass. Make the
  condition dead instead — `if cond && false` — so the mutation is valid.
- Read the failure text, not just the exit code. "Fails" and "fails with my message" are
  different results.
- Never express a threshold in terms of the constant it guards. Use an absolute value.
- Before asserting over a parser's output, print it once. An empty result satisfies every
  `for` loop.
- Add an absolute ceiling to any timing assertion. A sentinel of `budget + 30s` passes
  when the budget is set to five minutes.

## Generalisation

The shape is **an assertion that cannot distinguish the states you care about** —
because the input never arrived, because both branches produce the same value, or because
the oracle is derived from the thing under test. It is not specific to tests: any check
whose failure mode is silence has it, including monitoring, validation and health probes.
The same session found a name-validation heuristic that rejected `10-0-0-213` but accepted
`10-0-0-213.`, and the storage layer appended that dot — a filter that had never rejected
anything in production.

## Related

- [[a-cleaner-design-can-measure-worse-than-the-patch-it-replaces]]
