# Review gate: review each commit after it lands, gate the push

Date: 2026-09-01. Stale by default; re-measure before revisiting.

## 2026-09-23: review at the end of the turn, not before the next edit

Superseded in part. The pending commit no longer blocks edits and further
commits (`pending-review-guard.sh` is gone). A Stop hook, `review-gate --stop`,
blocks the turn from ending while HEAD is an unreviewed agent commit, once per
turn (`stop_hook_active` lets the second stop through). One reviewer over what
the turn committed clears it, and `record-review` stamps the whole unpushed
range, so a later hatched commit does not re-list what was reviewed. The
pre-push gate is unchanged and still the backstop, for Codex and humans alike.

Why: there is no human reviewer, so review has to be automatic, but it does not
have to be mid-task. The edit guard parsed shell redirects and heredocs to tell
a write from a read, needed `hook-bypass-guard.sh` (100 assertions) to stop the
agent routing around it, and stalled a median 7 minutes per denial. Anthropic's
Opus 5 guidance is to drop mid-task verification scaffolding and let the model
run to a stated completion; the end of the turn is that point. Also cut:
`commit-guard.sh` (amend and scratch staging, already in the harness prompt),
`pre-pr-review.sh` (duplicated the pre-push gate), `scope-tripwire.sh`, the
adherence meters, `guard-replay.py`.

Limits, stated so nobody mistakes the gate for a boundary: the Stop hook
nudges once per commit (`claude-stop-nudged`), then lets later turns end, and
only checks the session's cwd, so a `git -C other-repo commit` is caught only at
that repo's push. With the bypass guard gone, `git push --no-verify` is refused
by a `permissions.deny` rule in `.claude/settings.json` instead (Claude only;
Codex has no equivalent rule here).

## Decision

Two gates, one record (`bin/review-gate`, `bin/record-review`):

- **Post-commit, blocking.** A Claude commit marks HEAD pending. While HEAD is
  pending, the PreToolUse guard refuses Edit/Write and any further `git commit`
  in that repo, so nothing is built on an unreviewed commit. A reviewer run
  stamps HEAD and clears it. Reviewing after the commit keeps history: findings
  land as new commits. The cheap tier (`feature-dev:code-reviewer`, Sonnet) is
  enough for a commit-sized diff.
- **Pre-push, blocking.** The push passes if every commit in the range carries a
  stamp, or one reviewer saw the whole range (base..worktree or base..HEAD).
  Pre-commit is advisory only; a review taken before the commit still counts.
- **One hatch.** `claude-review-force` is consumed by whichever gate meets it
  first; touched before a trivial commit it stamps the commit and survives for
  the push.

Reviewer agents pin a model; nothing inherits the parent.

## Measurement

From local transcripts, all repos, 2026-08-04 (gate moved into git) to 2026-09-01.
Negative control: parsed reviewer spawns equal a raw substring count in the
busiest session.

| Measure                                       | Value     |
| --------------------------------------------- | --------- |
| Successful Claude-made commits                | 575       |
| Went through the hatch                        | 53%       |
| Had a reviewer run first                      | 21%       |
| Neither visible in the parent transcript      | 26%       |
| Commit attempts refused by the gate           | 163       |
| Median stall, refusal to next attempt         | 7.1 min   |
| Reviewer subagent runs since 2026-07-28       | 896       |
| Median reviewer run                           | 7.1 min   |
| Share of pool tokens spent inside reviewers   | 19.8%     |
| Median lines changed per commit (three repos) | 35 to 107 |

The 26% row includes reviews from forked `/code-review` runs, which clear the
gate without a spawn in the parent transcript. Reviewers ran on Opus 5 and 4.8;
`adversarial-reviewer` and `silent-failure-hunter` inherited the parent model.

## Why post-commit and push, not pre-commit or per-edit

Commits were already small, so diff size was not the cost. The cost was one
Opus-class reviewer per commit on the critical path, and the hatch was used on
more commits than the reviewer. Pre-commit review also folded fixes into the
reviewed commit, erasing what the reviewer changed. Per-edit review would run
nine times as often on half-built states with no evidence behind it: Claude
Code's `PostToolUse` cannot block, no widely used plugin gates per edit, and
Anthropic's own docs are two-tier, fast local review while iterating and deep
review before merging. Every PR-time reviewer in the field reviews landed
commits and expects fixes as follow-up commits. The one empirical thread is
that agent PRs grow past the size where review works, which is an argument for
small commits reviewed as they land.

## Prior art consulted

- Claude Code docs: hooks reference, `/code-review`, ultrareview, best practices.
- obra/superpowers, automazeio/ccpm, awesome-claude-code-hooks: none gate per edit.
- Brodzinski 2026-07-14 on 3x PR size under agents; SmartBear/Cisco review size curve.
- Willison 2026-08-22, Osmani 2026-06-15, Cherny (YC 2026): verification upstream of review.

## 2026-09-05: the same gate under Codex

The gate keys on the marker each harness exports into its tool shell:
`CLAUDECODE=1` for Claude Code, `CODEX_THREAD_ID` for Codex (verified by asking
`codex exec` 0.153.2 to print its environment). `.codex/hooks.json` mirrors the
PreToolUse guards in `.claude/settings.json`; Codex sends the same JSON field
names and honours the same deny shape (payloads captured 2026-09-05). Codex edits
through `apply_patch`, which the pending guard treats as an edit in cwd. The
Codex reviewer is the `reviewer` role in `.codex/agents/reviewer.toml`, pinned to
a model; `record-review` recognises it by `agent_type` on SubagentStop.

Codex refuses a hook until `/hooks` has recorded trust once. Trust is a hash of
the handler definition, not the script, so editing a script keeps trust and
editing `hooks.json` drops it; `setup.sh --dry-run` reports handlers with no
recorded trust. `tests/test-codex-hooks.sh` fails if the two manifests drift, and
`tests/test-review-gate.sh` runs every flow case a second time under the Codex
marker. Not mirrored: `rtk` (no Codex processor) and the ccpool pool warnings.
