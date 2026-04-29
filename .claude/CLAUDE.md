<!-- prettier-ignore -->
@/Users/sean/Developer/_dotfiles/AGENTS.md
@RTK.md

## Commits

- Run review + simplifier agents before committing
- Skip review gate ONLY for trivial changes (typos, config tweaks, single-line fixes): `touch /tmp/claude-commit-force-<session_id>`
- Skip-marker gotcha: PreToolUse fires before the Bash command runs. Chaining `touch && git commit` always denies because the touch hasn't executed yet. Touch the marker in a separate Bash call BEFORE the commit call. Re-touch after any pre-commit failure (prettier rewrite, lefthook), since the hook consumes the marker on use.
- If the diff touches more than ~3 files or includes logic/layout/routing changes, run the review; no exceptions

## Code Review

- Run `silent-failure-hunter` on error handling changes

## Paths

- Voice and style (all output, not just blog): read `~/.claude/writing-style.md`
- `.claude/` is reserved for agents, skills, settings -- not working docs.
