---
title: Dry-run release automation on one-commit branches, because "what counts as a release" is never what you assume
date: 2026-07-28
category: best-practices
module: release automation
problem_type: best_practice
severity: high
applies_when:
  - You are adopting release-please, semantic-release or any conventional-commit release tool
  - You are about to tell a maintainer or contributors which prefixes "trigger a release"
  - You are giving Dependabot a conventional `commit-message.prefix`
  - You are switching a repository to squash merging so a bot can read the title
tags:
  [
    release-please,
    conventional-commits,
    dependabot,
    squash-merge,
    verification,
    github-actions,
  ]
---

## The lesson

Release tools do not decide "is this releasable?" the way the docs' examples imply. Reason
about it and you will get it backwards in the dangerous direction, then ship a "fix" that
makes it worse. One scratch fork plus one branch per scenario settles it in minutes, and
the branches are one commit each so nothing else can explain the result.

## What happened

Adopting release-please for a Ruby gem, I told the maintainer: _a window with no `fix:`,
`feat:` or `!` opens no release PR._ Plausible -- those are the three prefixes every
tutorial shows mapping to patch/minor/major.

It is wrong. The rule is **parseability, not type.** Dry-runs of one-commit branches off
the last tag:

| Only commit since the tag           | Result                                                  |
| ----------------------------------- | ------------------------------------------------------- |
| `ci: ...`                           | releases **4.1.5**                                      |
| `build: ...`                        | releases **4.1.5**                                      |
| `Bump actions/checkout from 5 to 7` | `Considering: 0 commits` / `Would open 0 pull requests` |

Any parseable conventional type releases, patch at minimum. Only an unparseable subject
releases nothing.

Acting on the wrong model, I had already "fixed" Dependabot by giving it
`commit-message: {prefix: build}` so its PRs would pass a new title check. That would have
turned **every weekly dependency bump into a published gem** -- 4.1.5, 4.1.6, 4.1.7. The
unprefixed default subject was the only thing preventing it, and I removed it as an
improvement.

Two more assumptions that only survived because I tested them:

- GitHub's **default** squash message (`COMMIT_MESSAGES`) silently drops a breaking change:
  a PR titled `docs:` whose body carried a `fix!:` bullet computed **4.1.5**, not a major.
  `PR_TITLE` + `PR_BODY` computes it correctly and makes a `BREAKING CHANGE:` footer work.
- **HTML comments are not stripped** from a squashed message. Instruction comments in a
  pull request template land in `git log` verbatim, so under `PR_BODY` the template and the
  commit message are the same artifact and must be written as one. The trap this sets is
  vicious: a commented-out `BREAKING CHANGE:` hint at **column 0** in the template is still
  a note keyword to the parser. A review caught mine, and the dry-run confirmed it -- a PR
  titled `fix: correct a rounding error`, merged with the template body untouched, computed
  **5.0.0**. Moving the keyword mid-line (`beginning "BREAKING CHANGE:"`) computed 4.1.5.
  Test the template body itself, not a body you wrote by hand for the test.

## How to apply

Before documenting or enforcing any release rule:

1. Point at a **scratch fork**, never the real repo. Tags do not sync to forks -- push the
   last release tag first or the notes API 400s on `previous_tag_name`.
2. Build **one branch per scenario, one commit each**, off the last release tag, carrying
   whatever config file the tool reads from the target branch.
3. `--dry-run` each and grep for the decision, not the prose:
   `grep -E "Considering:|Would open|^title:"`.
4. Keep it as a script that recreates and deletes its own branches, so the claim stays
   re-runnable instead of becoming a story about a terminal session.

Corollary worth remembering on its own: **never give Dependabot a conventional prefix**
unless you actually want a release per bump. Its unparseable default is load-bearing.
Leave a comment saying so, or someone will tidy it up later.
