---
description: Capture a reusable lesson to docs/lessons. Use after closing an incident, landing a non-obvious fix, or finishing a measurement that changed a decision, in the same session while the reasoning is still loaded.
---

# Capture a Reusable Lesson

Write one lesson to `docs/lessons/` so the next session does not relearn it.

Invoke after closing an incident, landing a non-obvious fix, or finishing a
measurement that changed a decision -- **in the same session, while the reasoning
is still loaded**. A lesson written a week later is a summary; one written now is
evidence.

## 0. Should this exist at all?

Answer honestly before writing anything:

- **Would reading this before starting have saved time?** If no, stop. A
  restatement of the diff is worse than nothing -- it dilutes the corpus.
- **Is it already covered?** `rg` the existing `docs/lessons/` first. If a file
  covers it, extend that file rather than adding a near-duplicate.
- **Is it a lesson or a command?** Commands and environment gotchas belong in
  operations/reference docs. This directory is for things that change how you
  _decide_, not how you _invoke_.
- **Is it one lesson or two?** Two independent lessons are two files.

## 1. Name it for the lesson

The filename is the takeaway, as a claim a reader can disagree with:

- Good: `a-rename-is-silent-until-every-reference-is-updated.md`
- Good: `egress-cost-tracks-origin-miss-rate-not-client-count.md`
- Bad: `2026-02-06-docker-bug.md` (names the incident, not the lesson)
- Bad: `caching-notes.md` (names a topic, asserts nothing)

Place it under the category that matches: `best-practices/`, `process/`,
`logic-errors/`, `design-patterns/`, `integration-issues/`, `test-failures/`,
`database-issues/`, `performance-issues/`, `dependencies/`. Create the directory
if it is missing, and add it here once a second lesson lands in it.

## 2. Frontmatter

```yaml
---
title: <the lesson as a full sentence>
date: <YYYY-MM-DD it was learned, not today>
category: <directory name>
module: <affected area>
problem_type: <best_practice | logic_error | silent_noop | silent_regression | schema_change | integration | performance | test_failure>
severity: <high | medium | low>
applies_when:
  - <a situation where a reader should stop and read this>
tags: [<searchable keywords>]
---
```

`applies_when` is the highest-value field -- it is what makes the corpus
searchable by situation rather than by keyword. Write it as the trigger, not the
topic.

## 3. Body

Keep it short. Three things have to be there; the headings are yours to choose.

- **The claim, first.** State the lesson before any narrative, as something a
  reader could disagree with.
- **The evidence.** Enough of what happened to make it concrete, with the
  numbers if you measured any. Link the postmortem rather than retelling it. A
  lesson with a measurement is evidence; one without is an opinion.
- **The shape.** How to recognise the same mistake in a different subsystem,
  and what to do instead.

Then `[[other-lesson-name]]` links. Link liberally; a link to a file that does
not exist yet marks something worth writing.

`## The lesson` / `## What happened` / `## Guidance` / `## Generalisation` /
`## Related` is the common set, but the corpus has also grown `## The rule`,
`## The measurement`, `## The general shape`, and `## See also`. Use whichever
fits; don't pad a short lesson to fill five headings.

## 4. Commit it on its own

`docs(solutions): <the lesson>` as a **separate commit** from the fix. The fix
and the lesson have different audiences and different lifetimes, and a lesson
buried in a 12-file diff is not findable.

## Anti-patterns

- Writing one for every commit. Most work teaches nothing reusable.
- Recording what the code does. That is what the code is for.
- Hedging into uselessness. If you are not confident enough to state the lesson
  as a claim, you have not finished learning it yet.
- Leaving it in a gitignored path. If it is worth writing down, it is worth
  surviving the machine.
