# Claude usage economics: findings

Reference behind `usage-economics.md`; nothing points Claude here. From a 2026-07-03 investigation (ccusage + rate-limit history + web). Committed because Claude Code deletes `~/.claude/projects` transcripts.

## The model

The binding limit is the **weekly** (`seven_day`) pool, not the 5h session. It is **cost-weighted and model-aware**, not raw tokens (97% of volume is near-free `cache_read`), and **Opus-dominated** (73 to 99% of weekly cost). Best local proxy: ccusage dollars.

## Calibration (Max 20x, +50% promo, 2026-07-03)

- **~$45 ccusage API-equiv per 1% of weekly.** Cross-checked three ways ($673 / 15% is ~$44.8; corrected hand-roll; Opus-dominance transfers it across weeks).
- Pool floor ~$4 to $5k/week; ROI vs $200/mo ~90 to 110x. A **floor**: off-machine use (app, mobile, Docker/CI) burns the pool invisibly.
- **Tier-relative:** ~$45 now (20x + promo), ~$30 at 20x baseline (after 2026-07-13), ~$7.50 at Max 5x. Always stamp the tier.

## User dials and traps

- **Effort** (`/effort`): default `medium`; `high`/`xhigh` only for hard reasoning. ~76% fewer output tokens at medium vs high for equal completion; max is ~6x the turns of low. Biggest single cost swing.
- **Model** (`/model`): Opus for hard reasoning, Sonnet/Haiku for routine.
- **Trap, cheap + high effort:** a cheap model at high/xhigh/max costs more per task than Opus 4.8; the saving exists only at low or medium. Applies to Claude's subagent choices too.
- **Trap, Fable for routine:** Fable is 2x meter weight + 2x price (3 to 5x effective). Planner only, for hard/architectural/migration work (out-plans Opus, SWE-bench Pro 80% vs 69.2%), paid back by avoided rework, never routine.

## Notes

- **Opus 4.8 has no >200k premium** (full 1M at standard price; the premium was a 4.7/4.6 thing). Watching 200k for cost is obsolete.
- Effort is token emission, not a price multiplier: same `$/token`, more tokens.
- Huge contexts still cost quality (context rot) and drive `cache_read` volume.

## Tier timeline

- Max 5x from at least 2026-01-01; **Max 20x on 2026-07-01** (reset the window; Fable-5 re-release and the natural Wed-21:00-EDT reset also landed that day).
- **+50% weekly promo through 2026-07-13** (~1.5x baseline).
- 20x pool is ~4x 5x. Pre-upgrade, ~8 straight weeks pinned at the 5x cap: upgrade justified.

## Timezone

Transcripts are UTC; the weekly reset is a **fixed UTC instant + 7-day cadence**, so travel is irrelevant. `ccusage` buckets by local TZ by default: use `-z UTC`, never "9pm local."

## Durability

Claude Code CAN prune `~/.claude/projects/**/*.jsonl` on startup: the bug lets a high `cleanupPeriodDays` get ignored (30-day default wins on some updates/restarts) and keys deletion on mtime. Widespread (The Register 2026-06-30; issues #62272, #45903, #59248, #64999). Here: `cleanupPeriodDays: 100000` committed 2026-06-01; floor ~2026-04-29 (lost once) has held since, continuous week-over-week, no prune in 2+ months. Dormant now, not active. Keep durable files in a committed repo anyway, as a cheap hedge against re-firing.

## Tooling state

The history log (`~/.claude/rate-limit-history.jsonl`, outside the prune path) now stamps each weekly sample with `tier` (manual `TIER`, `USAGE_TIER` override) plus the session's cumulative `cost`/`session` (2026-07-03). `tier` is reliable; `cost` is a per-session checkpoint, not weekly spend (ccusage stays authoritative). Over weeks this makes `$/1%` measured, not inferred.

## Sources

ccusage (authoritative). Web: Anthropic pricing/effort docs; Artificial Analysis via MarkTechPost/digitalapplied (Sonnet vs Opus per-task); BenchLM / The New Stack (Fable vs Opus); Anthropic engineering (context); howborisusesclaudecode.com; The Register + GitHub issues (deletion).
