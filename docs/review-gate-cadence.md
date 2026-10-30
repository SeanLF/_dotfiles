# Review gate: review agent commits before they are pushed

Date: 2026-09-23; Stop hook removed 2026-10-29. Stale by default; earlier designs and their measurements are in
this file's git history.

## Decision

Nobody else reviews this work, so every agent commit is reviewed before it is
pushed, never mid-task. One record: stamps in
`claude-reviewed-commits`.

- **post-commit** marks an agent commit pending (`CLAUDECODE=1` or
  `CODEX_THREAD_ID`). Cherry-picks and rebases are not marked.
- **No Stop hook.** `review-gate --stop` still exists but is wired nowhere
  (Claude Code or Codex): the push is the one checkpoint.
- **SubagentStop** (`record-review`) stamps every unpushed commit when a reviewer
  agent finishes, and clears pending.
- **pre-push** refuses a push containing an unstamped commit.
- **Hatch:** `touch .git/claude-review-force` stamps one trivial commit, or lets
  one push through.
- `git push --no-verify` is refused by `permissions.deny` (Claude Code only).

Default reviewer is `/code-review medium`, Claude Code's own review, which runs as
a forked `general-purpose` subagent; `record-review` recognises it by the
`/code-review` task description in `background_tasks`, which Stop and
SubagentStop receive per the hooks reference.
`feature-dev:code-reviewer` (Sonnet, read-only) is the cheap alternative;
`adversarial-reviewer` (Opus) before a push. A Stop while a reviewer is already
running in the background is let through.

## Why this shape

- 2026-09-01 measurement (575 commits): a per-commit gate that blocked edits was
  hatched on 53% of commits, stalled a median 7 minutes per refusal, and spent 20%
  of the weekly pool inside reviewers. Blocking mid-task also needed a guard
  against the agent routing around it.
- Anthropic's Opus 5 guidance: drop mid-task verification scaffolding and let the
  model run to a stated completion. The end of the turn is that point.
- Stamps, not content hashes: the review always follows the commit, so there is
  nothing to match a pre-commit review against.

## Limits

A speed bump for an honest agent, not a boundary. The Stop hook sees only the
session's cwd, so `git -C other-repo commit` is caught at that repo's push.
`background_tasks` is session-wide, so a reviewer running for another repo also
lets this repo's Stop through; a later Stop, or the push, catches it.
Codex has no equivalent of the `--no-verify` deny, and changing
`.codex/hooks.json` drops Codex's trust until `/hooks` runs.
