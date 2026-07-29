---
title: A clean issue dedupe still misses the work already in flight; check open PRs by file path before designing anything
date: 2026-07-29
category: process
module: oss-contribution
problem_type: best_practice
severity: medium
applies_when:
  - about to propose an architecture or root-cause fix in a repo you do not maintain
  - you have finished deduping issues and are about to write code
  - the repo's open-PR count is comparable to or larger than its open-issue count
tags: [github, gh-cli, oss, prior-art, duplicate-work, contribution, rtk]
---

## The lesson

Deduping **issues** proves the problem is unreported. It says nothing about
whether the _solution_ is already written. In a repo with a large PR queue, the
current thinking lives in open PRs, not issues. An issue tells you what someone
noticed; a PR tells you what someone is already doing about it. Search the PR
frontier, scoped to the files you intend to touch, before you design.

## The command

One shot, no per-PR loop (`gh pr list --json files` works; `gh pr view` per PR
is unnecessary):

```bash
gh pr list -R OWNER/REPO --state open --limit 200 --json number,title,files \
  | jq -r --arg p 'src/discover/' '
      .[] | select(any(.files[]?.path; startswith($p))) | "#\(.number)  \(.title)"'
```

Path-scoped beats keyword search: a PR that collides with you is defined by the
code it edits, not by whether its title happens to share your vocabulary.

## The evidence

Contributing to `rtk-ai/rtk`: 863 open issues, **906 open PRs**.

The issue dedupe was thorough and correct — roughly 40 queries, five near-miss
issues read in full, two prior duplicates found already closed as such. It
established that the defect was genuinely unreported, and the issue filed on that
basis was sound.

Then two full turns went into deriving a root-cause architecture: proving the
transcript-to-database join fails (2.5% raw, 4.3% after canonicalising both
sides), establishing that the stored `original_cmd` is a synthesised
post-expansion label rather than anything typed, and proposing hook-side logging
of the pre-expansion command.

PR #3206 — open four days earlier, titled `fix(discover): log real hook decisions
instead of guessing coverage retroactively` — had already implemented it, and
better. It joins on `tool_use_id` rather than command text, which makes the
expansion problem _irrelevant_ instead of solvable. The command above lists it
eighth, with a title no one could misread.

Cost: two turns of design work, and a proposal that would have been published
without it.

## The shape

The failure mode is a thorough search with a structural blind spot, which is
more dangerous than a lazy one because it produces confidence. The question
"has anyone reported this?" and the question "is anyone fixing this?" query
different surfaces, and only the first is a dedupe.

Trigger to stop and run it: the moment the work shifts from _fixing a defect_ to
_proposing a design_. A design implies the maintainers have a direction, and if
they do, it is visible in the PR queue.

Corollary that generalises past GitHub: before proposing an architecture in
someone else's system, look for the half-built version of it. The `hook-audit.log`
already in that codebase was a second instance of the same blind spot — a
mechanism proposed as new that already shipped, opt-in, unread by the code that
needed it.

## Related

- [[a-default-reference-sweep-skips-hidden-and-ignored-files]] — the same shape:
  a search that looks exhaustive but is silently scoped.
- [[two-failed-variants-mean-the-premise-is-wrong]] — the secondary lesson here:
  2.5% then 4.3% read as tuning progress and masked that the join _key_ was wrong,
  not the join technique.
