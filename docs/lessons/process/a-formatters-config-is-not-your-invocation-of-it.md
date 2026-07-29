---
title: A formatter that reverts your change is configured differently than your invocation of it, so read the config before reformatting twice
date: 2026-07-28
category: process
problem_type: best_practice
module: lefthook, tooling
severity: medium
applies_when:
  - A pre-commit formatter rejects a file you just formatted
  - Running a linter or formatter manually to satisfy a hook
  - Two runs of the same tool disagree about the same file
tags: [lefthook, shfmt, prettier, formatting, pre-commit, config]
---

# A formatter's config is not your invocation of it

## The lesson

`shfmt` rejected a commit. I ran `shfmt -w` on the files, verified clean with
`shfmt -d`, and committed again. It rejected the commit again, this time asking
for the **opposite** indentation to the one my own run had just produced.

The tools were not disagreeing with themselves. `lefthook.yml` ran:

```yaml
run: mise x -- shfmt -d -i 2 -ci {staged_files}
```

`-ci` indents `case` branches; bare `shfmt` does not. My run and the hook's run
were two different formatters wearing the same name. Re-running the naked
command a third time would have produced the same rejection a third time.

Reading `lefthook.yml` and running `shfmt -w -i 2 -ci` fixed it in one pass.

## Guidance

When a formatter rejects work you just formatted, the next action is **read the
hook config**, not run the formatter again. Grep the repo for the tool name:

```sh
rg -uu -n 'shfmt|prettier|ruff' lefthook.yml .pre-commit-config.yaml package.json
```

Then invoke it with the flags you find, and prefer the same runner the hook uses
(`mise x --`, `npx`, the pinned binary) so you also match the version.

Two symptoms distinguish this from an ordinary formatting miss:

- The tool asks for something **different** from what it asked for last time.
- The diff it wants **reverses** an edit the same tool just made.

Either one means two configurations, not one stubborn file.

## Generalisation

A tool invoked by name is not a fixed behaviour, it is a behaviour plus a
config resolution you did not perform. Any wrapper (a git hook, CI, a task
runner, a Makefile) is entitled to supply flags you never see. When the wrapper
and your shell disagree, the wrapper is the source of truth, because it is the
one gating the work.

Related: [[a-tool-that-exits-zero-may-have-written-nothing]],
[[the-dangerous-flag-collisions-are-the-ones-that-succeed]].
