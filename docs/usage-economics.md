# Claude cost levers (for Claude Code)

What Claude Code can do mid-task to save the weekly pool. Background and calibration: `usage-economics-findings.md` (not needed to act).

## Levers Claude controls

- **Delegate to cheap subagents.** Send read/search/mechanical work to `haiku`/`sonnet` subagents (set model on `Agent`/`Task`; set effort in workflows or the agent's definition). Offloads tokens off the main loop and isolates context. The biggest lever.
- **Few subagents, not many** (sprawl multiplies cost).
- **Lean context:** read just-in-time, delegate to isolate, compact.
- **Never a cheap model at high effort** (costs more per task than Opus).
- **Durable outputs outside `~/.claude/projects`** (the pruner deletes that tree).

## Not Claude's to set

Main-loop `/effort` and `/model` are user dials: recommend, do not assume you can change them.
