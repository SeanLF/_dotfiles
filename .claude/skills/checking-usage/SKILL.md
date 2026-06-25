---
name: checking-usage
description: Use when you need to know the current time and how much Claude usage budget is left (session/5h window and weekly pool) - e.g. deciding whether to keep going in a long or autonomous loop, or before claiming a budget-bounded task is done. Reports time, session %, weekly %, reset countdowns, pace, and a keep-going-or-stop verdict.
---

# Checking time + remaining usage budget

Answers two questions in one command: **what time is it** and **how much usage budget is left** — both the session (5-hour) window and the weekly pool, with reset countdowns and a decision.

## Run it

```bash
ruby ~/.claude/skills/checking-usage/usage.rb
```

That prints everything. No arguments. Read the `VERDICT` line — it's the decision, not just numbers.

## How it works (and its one limitation)

The live budget (`rate_limits.five_hour` / `seven_day`) is delivered _only_ to the status-line process by Claude Code — there is no CLI or API for it. So `~/.claude/statusline-command.rb` mirrors that payload to `~/.claude/usage-cache.json` on every render, and this script reads that cache.

This is the officially documented source — the Claude Code status-line docs expose exactly `rate_limits.five_hour` / `.seven_day` (`used_percentage` + `resets_at`). There is **no** pollable REST API for a Pro/Max subscriber's budget: the Admin Usage/Cost API is org/API-key billing (not subscription windows), and the only on-demand pull (`GET /api/oauth/usage`) is undocumented and rate-limit-fragile. The status-line payload is the stable path.

**Two limitations, both honest:**

- **Freshness** — the data is only as fresh as the last status-line render. Interactive: refreshes every turn (seconds old). Pure background job with no TUI: can be stale or absent — the script says so (`STALE` / "no cache") instead of guessing. If stale and it matters, get an interactive window to render once, then re-run. Never fabricate the figures.
- **`seven_day` is the ALL-MODELS weekly window.** The separate **Sonnet-only weekly cap** that `/usage` shows is NOT in this payload (Claude Code issue #27915). So WEEKLY here can read healthy while a Sonnet-specific weekly limit is the actual constraint. For Sonnet-heavy work, treat a healthy weekly % as necessary-but-not-sufficient and sanity-check `/usage` directly before a big push.

## The decision rule (read this)

The mistake this exists to prevent: **stopping with weekly budget left because the session window looked full.** They are different things.

- **SESSION (5h) near full** → _temporary_. The window resets in a few hours. If the weekly pool still has room, this is NOT "done" — it's "pause and resume after the reset." Wait it out or hand back, don't declare the task finished.
- **WEEKLY pool near full** → the real stop signal. Land in-flight work and stop for the week.
- **Both have room** → keep going. If you were asked to spend a budget (e.g. "loop until my limits are used"), _spend it_ — under-pace means push harder, not coast.

`pace` tells you if you're ahead of or behind an even burn; `budget: ~N% safe to spend today` is how much of the weekly pool you can use today and still last the window.

## Tunables (env, optional)

- `USAGE_SESSION_FULL` (default 92) — session % that counts as "almost full"
- `USAGE_WEEKLY_LOW` (default 90) — weekly % that triggers WIND DOWN
- `USAGE_STALE_SECS` (default 900) — cache age before it's flagged STALE
