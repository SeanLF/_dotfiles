---
title: A default reference sweep skips hidden and ignored files, so "no matches left" is not proof the rename is complete
date: 2026-07-28
category: best-practices
module: tooling, refactoring
problem_type: silent_noop
severity: high
applies_when:
  - Verifying that a rename or path change caught every reference
  - Concluding something is absent because a search returned nothing
  - Sweeping a repo for a string before deleting or moving the target
tags: [ripgrep, search, rename, hidden-files, gitignore, silent-failure]
---

# A default reference sweep skips hidden and ignored files

## The lesson

`rg` skips hidden files and honours `.gitignore` **by default**. So a
post-rename sweep that returns nothing has not proven the rename is complete.
It has proven the rename is complete _in the subset of the tree the search
agreed to look at_, which is not the same claim and is not the one you need.

Renaming `docs/solutions/` to `docs/lessons/` across five repos, the sweep
`rg -l 'docs/solutions' ~/Developer` returned clean. Seven references remained:

| file                              | why it was skipped |
| --------------------------------- | ------------------ |
| `.claude/commands/lesson.md` (×3) | hidden directory   |
| `.claude/learnings.md`            | hidden directory   |
| `.claude/tasks/todo.md`           | hidden directory   |
| `CLAUDE.local.md`                 | gitignored         |
| `scratch/handover-2026-07-25.md`  | gitignored         |

`rg -uu` found all seven in one pass.

The expensive one was `CLAUDE.local.md`. It is gitignored, so it never appears
in `git status`, and it is loaded into the assistant's context every session.
The rename would have left a config file silently pointing at a directory that
no longer exists, and nothing in the repo would ever have flagged it.

## Guidance

Use `rg -uu` for any sweep whose purpose is to prove absence. Reserve the
default mode for finding something you expect to exist, where a miss costs you
one more search rather than a false conclusion.

The two cases are not interchangeable:

- **Finding**: default is right. Fewer results, faster, less noise.
- **Proving absence**: `-uu` is mandatory. The whole value of the answer is
  its completeness.

Config and state files are the ones that bite. They are disproportionately
hidden or gitignored, disproportionately consumed by tooling rather than by
code, and therefore disproportionately absent from every other check you run.

## Generalisation

Any tool with a helpful default has a scope you did not choose. When the output
is a _negative_ claim, the default scope becomes part of the claim, silently.
Before trusting "nothing found", ask what the tool declined to look at.

Related: [[a-rename-is-silent-until-every-reference-is-updated]],
[[the-dangerous-flag-collisions-are-the-ones-that-succeed]].
