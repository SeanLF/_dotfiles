---
name: checking-usage
description: Use when you need the current time and how much Claude usage budget is left (session/5h window + weekly pool) - deciding whether to keep going in a long or autonomous loop, or before claiming a budget-bounded task is done. Reports time, session %, weekly %, reset countdowns, pace, and a keep-going-or-stop verdict.
---

# Checking time + remaining usage budget

Answers "what time is it" and "how much budget is left" (session 5h window + weekly pool, with reset countdowns and a decision) in one command.

## Run it

```bash
ruby ~/.claude/skills/checking-usage/usage.rb
```

No arguments. Read the `VERDICT` line — it's the decision, not just numbers.

## The decision rule (the reason this exists)

The mistake this prevents: **stopping with weekly budget left because the session window looked full.** They're different things.

- **SESSION (5h) near full** → _temporary_. Resets in hours. If the weekly pool has room, this is "pause and resume after the reset," NOT "done."
- **WEEKLY pool near full** → the real stop signal. Land in-flight work and stop for the week.
- **Both have room** → keep going. If asked to spend a budget, _spend it_ — under-pace means push harder.

`pace` shows if you're ahead of or behind an even burn. The `pace guide` (~N%/day) is an even-burn share to make the weekly pool last — a pacing hint, **not a hard daily cap** (there is no daily quota), and it can't see how much of today you've already spent.

## Two honest limitations

- **Freshness** — the numbers are only as fresh as the last status-line render (the payload reaches only that process; there's no pollable API). Interactive: seconds old. Pure background job with no TUI: can be stale/absent — the script says so (`STALE` / "no cache") instead of guessing. If stale and it matters, get an interactive window to render once, then re-run.
- **`seven_day` is the ALL-MODELS weekly window.** The separate Sonnet-only weekly cap that `/usage` shows is NOT in this payload ([issue #27915](https://github.com/anthropics/claude-code/issues/27915)). For Sonnet-heavy work, treat a healthy weekly % as necessary-but-not-sufficient and check `/usage` before a big push.

## Tunables (env, optional)

- `USAGE_SESSION_FULL` (default 92) — session % that counts as "almost full"
- `USAGE_WEEKLY_LOW` (default 90) — weekly % that triggers WIND DOWN
- `USAGE_STALE_SECS` (default 900) — cache age before it's flagged STALE
