<!-- prettier-ignore -->
@/Users/sean/Developer/_dotfiles/AGENTS.md
@RTK.md

## Commits

- Run review + simplifier agents before committing
- Skip review gate ONLY for trivial changes (typos, config tweaks, single-line fixes): `touch /tmp/claude-commit-force-<session_id>`
- Skip-marker gotcha: PreToolUse fires before the Bash command runs. Chaining `touch && git commit` always denies because the touch hasn't executed yet. Touch the marker in a separate Bash call BEFORE the commit call. Re-touch after any pre-commit failure (prettier rewrite, lefthook), since the hook consumes the marker on use.
- Pre-PR self-review gate: pushing or opening a PR needs `touch /tmp/claude-pr-review-done-<session_id>` in a **separate** Bash call first (same PreToolUse-fires-first gotcha — chaining `touch && git push` always denies). The hook consumes it per use, so re-touch before each push/PR.
- If the diff touches more than ~3 files or includes logic/layout/routing changes, run the review; no exceptions

## Code Review

- Run `silent-failure-hunter` on error handling changes

## Paths

- `.claude/` is reserved for agents, skills, settings; not working docs.
