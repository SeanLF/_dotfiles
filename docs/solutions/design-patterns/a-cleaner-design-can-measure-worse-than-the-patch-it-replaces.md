---
title: A cleaner design can measure worse than the patch it replaces; ask what the primitive you are removing was buying
date: 2026-07-25
category: design-patterns
module: any refactor that swaps a primitive
problem_type: best_practice
severity: high
applies_when:
  - You are replacing rename/atomic-write/symlink/lock with something more explicit
  - You have argued that a narrow fix is "just a mitigation" and a rewrite is the real answer
  - A design feels obviously cleaner but you have not measured the old one
  - You are about to widen a PR because the small version leaves a documented caveat
tags: [architecture, refactoring, atomicity, filesystem, measurement, yagni]
---

## The lesson

"Cleaner" is a hypothesis, not a result. Before swapping a primitive, enumerate what it
was buying you — atomicity, symlink semantics, zero disk space, label preservation,
ordering — and test those specifically. A rewrite that ignores one of them can be
measurably worse than the patch it was meant to supersede.

## What happened

A daemon backed up `/etc/resolv.conf` by **renaming** it, then renamed a staged file into
place. A revert landing between those two renames could consume the backup, so I argued
the mechanism was fragile and rewrote it to **copy** the original instead — durable
record, never absent, obviously cleaner.

Adversarial review plus measurement found the rewrite was worse on three counts:

- **Symlinks destroyed.** `os.Open` follows a symlink, so the backup recorded the target's
  _content_, and restore wrote a regular file. Verified primitive: renaming a regular file
  onto a symlink path gives `l -> -`; renaming the link itself round-trips `l -> l`. A
  symlinked `/etc/resolv.conf` is the default on systemd-resolved and NetworkManager hosts,
  so this was a certainty on every cycle, not a race.
- **The race got worse.** My copy helper staged through the same shared temp path the
  writer used, letting a concurrent process publish the wrong file. Measured over 500
  trials each: **baseline 1.0% loss, my "fix" 3.0%.** I tripled the failure I set out to
  remove.
- **New failure mode.** Restore now needed free disk space; rename needed none. On the
  small-`/etc` router platforms this shipped to, a full disk meant you could no longer
  revert.

And the premise was wrong. I argued the vulnerable window was large "because the write
path is slow". Reading the original properly, it staged the temp file _before_ moving the
backup — the exposed window was two renames, microseconds. I wrote 250 lines to close a
microsecond window and bought a certainty in exchange.

Measured outcome of the whole spike: **682 insertions across 11 files, versus 361 across 5
for the narrow fix** — and the narrow fix had no regression.

## Guidance

- Write down what the existing primitive guarantees before replacing it. `rename` is
  atomic, needs no space, moves a symlink as a symlink, and preserves the inode's labels.
  Which of those does your replacement keep?
- Test the specific properties, not the happy path: symlinked target, disk full, read-only
  filesystem, a second process doing the opposite operation concurrently.
- Give every operation its own scratch path. A shared temp file is a cross-process channel.
- Measure the _old_ failure rate before claiming to improve it. "1% under a deliberate
  race" is a different problem from "fails every time".
- A documented caveat on a small change is often better than an undocumented certainty on
  a large one.

## Generalisation

The shape is **replacing a primitive whose guarantees are implicit**. Filesystem calls are
the classic case, but the same applies to swapping a mutex for a channel (a goroutine
blocked on a mutex is not durably blocked, so a fake-clock test harness will stop advancing
time), an atomic for a lock, or a library's default timeout for your own. The guarantees
you did not enumerate are the ones you will lose silently.

Corollary on process: the argument "this is only a mitigation, the clean fix is X" is
seductive and was wrong here. Mitigation versus cure is a claim about outcomes, so it needs
a measurement, not an aesthetic.

## Related

- [[a-passing-test-may-be-asserting-nothing]]
