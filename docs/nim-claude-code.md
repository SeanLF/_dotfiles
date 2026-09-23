# NVIDIA NIM free models for Claude Code (`ccnim`)

Date: 2026-08-29 (run 3). Stale by default; model ids expire within weeks. The
full measurement log is in this file's git history.

## Decision

build.nvidia.com is a free trial surface, not an API provider: no SLA, and the
catalogue churns (run 2 lost five of ten ranked models in a month). `ccnim` is a
free ride when it is up. Keep it fail-fast and hand off to `ccl` (local
llama.cpp) or real Claude; don't harden it.

- **Default:** `moonshotai/kimi-k3`. 2.5 s on a 92 KB payload, 6.6 s end to end.
- **Fallback:** `deepseek-ai/deepseek-v4-flash-0731`. 18 s on the same payload.
- **Not in a loop:** `deepseek-v4-pro-0813` (146 s), `glm-5.2` (91 s to first
  token, then delisted), `minimax-m3` (429 on 3 of 5 paced requests),
  `gpt-oss-120b` (all reasoning, 0.6 to 100 s+).

## What to know before changing `ccnim`

- **Rank on a realistic payload or do not rank.** Claude Code sends ~113 KB per
  request. Short-prompt runs ranked `pro` first; at 92 KB it is 60x slower.
- **Probe for retirement.** NIM sends an RFC 8594 `deprecation:` header (on 200s
  and 429s) only for models scheduled to die. One 1-token call per model reads it.
- **Two limiters per model.** Concurrency (~6) rejects only the excess and costs
  nothing. The rate limit (well under the documented 40 RPM, and falling with
  cumulative use) triggers a lockout of 10 to 60 minutes. Cap at 6 concurrent and
  pace per model.
- **429 is not 402.** 429 is rate or capacity; 402 is exhausted trial credits.
- **No context-window API.** `/v1/models` has none; the `featured-models.json`
  feed is abandoned; the `max_tokens` probe now returns an empty body. Most models
  cap output at 8,192 tokens. Served context is below native (GLM-5.2: ~198k, not 1M).
- **Claude Code** warns on unknown model ids and assumes 200k; set
  `CLAUDE_CODE_MAX_CONTEXT_TOKENS` or `modelOverrides` if the window matters.

## Proxy: Olla

NIM's hosted gateway is OpenAI-compatible only, so a translation proxy is
required. Olla maps `reasoning_content` to thinking blocks. It does not fail over
on a 429 (a real HTTP response is streamed straight back), and its default 30 s
`server.read_timeout` reports a slow model as "unable to connect to LLM backend";
it is raised to `5m` in `~/.config/olla/config.yaml` (`write_timeout` stays `0s`
or streaming breaks).

429 failover exists as a proof of concept on SeanLF/olla branch
`feature/429-alias-model-failover`, for
[thushan/olla#193](https://github.com/thushan/olla/issues/193). No maintainer
reply since 2026-07-26 and upstream has moved 300+ commits past the branch point;
let it lapse unless #193 moves.
