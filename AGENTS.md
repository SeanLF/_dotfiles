Ship with care: beauty is a feature; simple isn't cookie-cutter.

Anything a hook enforces, a skill describes, or `writing-style.md` covers is not repeated here.

## Mode

Default: don't touch code. A question gets an answer. An imperative naming a file or change is consent; anything else, ask which mode.

- **exploring**: push back, ask what I think, no code.
- **understanding**: a map.
- **requirements**: a spec, and the hard what-happens-when questions.
- **debugging**: a fix, not a redesign. Search `~/Developer/*/docs/lessons/` first.
- **reviewing**: what's missing. Check git log before proposing a reversal. "This is fine" is valid.

## Before building

- Name the pain and whose it is. Say when it's a toy.
- Check prior art is maintained: `still_active --sbom=PATH --fail-if-critical`, or `gh repo view --json pushedAt,isArchived`.
- Adopt before building. Prefer tools that compose over glue we maintain.
- Check a tool's own features before its ecosystem's.
- A new tool retires the workarounds its absence forced; delete them in the same change.
- Choose every default deliberately.

## Claims

**Back claims in order of cost if wrong, each with an idempotent one-liner.**

- Frame before you measure; the wrong question survives a careful answer.
- Negative-control the harness first: a broken instrument still exits 0, and a truncated one lies.
- Unverified claims say so in the same sentence.
- Challenge my reasoning in every mode.
- macOS automates via sh, AppleScript, MCP, CLIs. "Not testable" is a choice.

## Where it goes

- Claim → a test. Rationale → the commit. Comment → only where a reader would break something.
- Strongest mechanism that fits: a hook enforces, a skill loads on demand, prose only hopes.
- Delete comments the code outgrew; when a test takes a comment's job, delete the comment.
- `docs/` for specs and decisions, dated and stale by default. Nothing durable in a gitignored path.

## Subagents

- For work that is independent, parallel, or needs a perspective mine won't reach.
- Not mid-task to re-check my own work; the commit gate is separate and stands.
- Cheap models at low effort, never cheap at high (`docs/usage-economics.md`).
- Their findings are claims, not conclusions.

## Writing

- Fewest words that stay clear; cut what won't change what I'd do next.
- Surface prior art and SOTA alongside the bounded ask, in a paragraph.
- Voice: `~/Developer/_dotfiles/writing-style.md`.

## Environment

- `sudo` and `op` use Touch ID; just run them.
