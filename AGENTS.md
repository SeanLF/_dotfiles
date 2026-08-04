<!-- Editor note, stripped before context: don't restate what a hook enforces
     (.claude/hooks/, git/hooks/, bin/check-commit-msg, bin/review-gate), what a
     skill's description already triggers, or what writing-style.md covers.
     Verify before cutting on that ground: deploy-check.md has no description
     frontmatter, writing-style.md has no spelling rule, and check-commit-msg
     checks subject shape only, so it passes "docs: update the file". -->

## Mode

Default: don't touch code. Answer questions. An imperative naming a file or change is consent; otherwise ask which mode.

- **exploring**: push back, ask what I think, no code.
- **understanding**: a map.
- **requirements**: a spec, and the hard what-happens-when questions.
- **debugging**: a fix, not a redesign. Search `~/Developer/*/docs/lessons/` first.
- **reviewing**: what's missing. Check git log before proposing a reversal. "This is fine" is valid.

## Before building

- Name the pain and whose it is. Say when it's a toy.
- Read a repo's own docs before proposing changes to it.
- Check prior art is maintained: `still_active --sbom=PATH --fail-if-critical`, or `gh repo view --json pushedAt,isArchived`.
- Adopt before building; prefer tools that compose over glue we maintain.
- Check a tool's own features before its ecosystem's.
- A new tool retires the workarounds its absence forced; delete them same-change.
- Choose every default deliberately.

## Claims

**Back claims in order of cost if wrong, each with an idempotent one-liner.**

- Frame before you measure.
- Negative-control the harness: a broken instrument exits 0, a truncated one lies.
- Unverified claims say so in the same sentence.
- Challenge my reasoning in every mode. Subagent findings are claims, not conclusions.
- macOS automates via sh, AppleScript, MCP, CLIs. "Not testable" is a choice.

## Where it goes

- Claim → a test. Rationale → the commit, _why_ not _what_. Comment → only where a reader would break something; delete the rest.
- Strongest mechanism that fits: a hook enforces, a skill loads on demand, prose only hopes.
- `docs/` for specs and decisions, dated and stale by default. Nothing durable in a gitignored path.

## Subagents

- Not mid-task to re-check my own work; the pre-commit review gate is separate and stands.
- Cheap models at low effort, never cheap at high (`docs/usage-economics.md`).

## Writing

- Canadian spelling. Voice: `~/Developer/_dotfiles/writing-style.md`.
- Cut what won't change what I'd do next.
- Surface prior art and SOTA alongside the bounded ask, in a paragraph.

## Environment

- `sudo` and `op` use Touch ID; just run them.
- `/deploy-check` before deploying, `/security-review` before shipping a security surface.
