# NVIDIA NIM free models for Claude Code (`ccnim`)

How the free hosted NVIDIA NIM models actually behave when driven by Claude Code
through the Olla proxy. Every number below is **measured against the live hosted
API** (`integrate.api.nvidia.com/v1`) or pulled from a cited primary source — not
copied from a benchmark leaderboard or an LLM's opinion.

- **Measured:** 2026-07-06, single-sample per model, free tier, from Ottawa.
- **Why this exists:** an earlier model ranking was taken from ChatGPT's tier list,
  which ranked models by reputation, not data. It put `gpt-oss-120b` at #1 — the
  slowest, weakest-agentic model on the list. This doc replaces that with hard data.

> **Set expectations first: this is a trial surface, not an API provider.** NVIDIA
> positions build.nvidia.com as a free "trial experience... for experimentation,
> development, testing and research" — a demo funnel toward self-hosted NIM containers and
> paid DGX Cloud. There is no SLA and the reliability will not improve, because reliability
> isn't the product. `ccnim` is therefore a "free ride when it's up," never load-bearing.
> Don't over-invest in hardening it; the reliable paths are `ccl` (local Ollama), self-host,
> or real Claude. Design `ccnim` to **fail fast and hand off**, not to paper over a demo
> endpoint's limits.

---

## TL;DR — what to actually run

**Default: `z-ai/glm-5.2`.** Best agentic score of any free NIM model, reliable tool
calls, no reasoning leakage, ~35 tok/s. The `ccnim` default is correct.

**Good alternates:** `moonshotai/kimi-k2.6` (fast, clean), `mistralai/mistral-large-3-675b`
(fastest measured — 111 tok/s), `mistralai/mistral-medium-3.5` (fast, lower intelligence).

**Avoid on the free hosted tier:**

- `deepseek-ai/deepseek-v4-pro` — great benchmark, but **79s to first token, 2.7 tok/s,
  tool calls time out**. This is the "thinks then shows nothing in the UI" symptom.
- `deepseek-ai/deepseek-v4-flash` — dumps output into `reasoning_content`; renders blank
  if the proxy doesn't map that field.
- `openai/gpt-oss-120b` — ChatGPT ranked it #1; it has the **worst** agentic score here
  and is slow/variable on NIM.
- `qwen/qwen3.5-122b`, `google/gemma-4-31b`, `meta/llama-3.3-70b` — timed out / 1-2 tok/s.

---

## Model ranking (intelligence + measured NIM reality)

`agentic` / `coding` / `intel` are Artificial Analysis indices (the agentic index is the
one that matters for Claude Code). TTFT and tok/s are measured on NIM (sequential run,
uncontended). `ctx` is what **NIM actually serves** where known (see [context](#context-windows--output-caps)).

| Model                            | agentic | coding | ctx   | TTFT    | tok/s   | Claude Code verdict                                  |
| -------------------------------- | ------- | ------ | ----- | ------- | ------- | ---------------------------------------------------- |
| **`z-ai/glm-5.2`**               | **43**  | 69     | 198k  | 1.0s    | 35      | ✅ **default** — clean tool calls, no reasoning leak |
| `moonshotai/kimi-k2.6`           | 30      | 56     | 256k  | 5.5s    | 53      | ✅ fast, clean                                       |
| `mistralai/mistral-large-3-675b` | —       | —      | 256k  | 0.3s    | **111** | ✅ fastest, clean                                    |
| `qwen/qwen3.5-397b-a17b`         | 20      | 48     | 256k  | 1.5s    | 40      | ✅ reliable, mediocre agentic                        |
| `mistralai/mistral-medium-3.5`   | 19      | 47     | 256k  | 0.6s    | 48      | ✅ fast, lower intelligence                          |
| `minimaxai/minimax-m3`           | 35      | 59     | 192k  | 3.7s    | 6       | ⚠️ 2nd-best agentic, too slow on NIM                 |
| `nvidia/nemotron-3-ultra-550b`   | 27      | 49     | 1M    | 0.6s    | 16      | ⚠️ slow, leaks reasoning_content                     |
| `openai/gpt-oss-120b`            | **13**  | 30     | 131k  | 14-28s  | 14-47   | ⚠️ worst agentic, slow/variable, leaks reasoning     |
| `deepseek-ai/deepseek-v4-flash`  | 31      | 56     | 1M*   | var     | var     | ❌ output → reasoning_content, blank-UI risk         |
| `deepseek-ai/deepseek-v4-pro`    | 36      | 59     | 256k  | **79s** | 2.7     | ❌ tool calls time out — the dead-air symptom        |
| `qwen/qwen3.5-122b-a10b`         | —       | —      | 256k* | timeout | 0       | ❌ times out on NIM                                  |
| `google/gemma-4-31b-it`          | 14      | 43     | 256k* | timeout | —       | ❌ times out on NIM                                  |
| `meta/llama-3.3-70b-instruct`    | —       | —      | 128k* | timeout | ~2      | ❌ 1.7 tok/s, unusable                               |

`*` context is the model's native/card figure, not confirmed as NIM-served (not in the
featured-models feed).

**Sequential vs parallel:** all 13 models probed concurrently finish in ~121s wall (vs
~11 min sequential) — parallel pays the _slowest_ model, sequential pays the _sum_. But
under 13-way concurrency the slow tail degrades further (shared-infra contention) while
fast models stay stable. Fast-model tok/s is trustworthy; slow-model numbers are a
ceiling.

---

## Claude Code compatibility notes

Claude Code hard-requires tool calling and expects assistant turns to have visible text.
Two failure modes showed up:

1. **`reasoning_content` leakage → blank UI.** The hosted OpenAI endpoint returns a
   `reasoning_content` field (undocumented) for some models. Measured leakage into that
   field instead of `content`: `deepseek-v4-flash` (1000+ chars), `gpt-oss-120b` (~250),
   `nemotron-3-ultra` (~170). **If the proxy doesn't map `reasoning_content` → Anthropic
   thinking/text, these render as empty turns.** This is the single most important proxy
   fix.
2. **Throughput so low it reads as a hang.** `deepseek-v4-pro` takes 79s to first token
   and its tool call timed out at 100s. In an agent loop (plan → edit → tool) this is
   indistinguishable from a crash. Not a bug in the setup — the model is just that slow
   on free NIM.

Every model that returned did emit valid OpenAI `tool_calls` — tool _format_ was never
the problem; throughput and reasoning-field routing were.

---

## Context windows & output caps

**There is no supported NVIDIA API for context window.** `GET /v1/models` and
`/v1/models/{id}` return only `id`, `object`, `created`, `owned_by`. Per-model doc pages
state context as prose only.

**The one programmatic source** is an undocumented feed that powers the build.nvidia.com
carousel — it carries `context` and `max-output`, and these are **NIM's served values**,
not the models' native maxes:

```
https://assets.ngc.nvidia.com/products/api-catalog/featured-models.json
```

| Model                               | served context | max output |
| ----------------------------------- | -------------- | ---------- |
| `nvidia/nemotron-3-ultra-550b-a55b` | 1,048,576      | 8,192      |
| `nvidia/nemotron-3-super-120b-a12b` | 1,000,000      | 8,192      |
| `moonshotai/kimi-k2.6`              | 262,144        | 8,192      |
| `deepseek-ai/deepseek-v4-pro`       | 262,144        | 16,384     |
| `qwen/qwen3.5-397b-a17b`            | 262,144        | 16,384     |
| **`z-ai/glm-5.2`**                  | **202,752**    | 8,192      |
| `minimaxai/minimax-m3`              | 196,608        | 8,192      |

Two gotchas this exposes:

- **GLM-5.2 serves ~198k, not the 1M its native spec claims.** MiniMax-M3 serves ~192k,
  not 1M. Don't advertise 1M in the statusline.
- **Output is capped at 8,192 tokens** for most models (16k for deepseek/qwen). A real
  constraint for large multi-file edits — the model can't emit a big diff in one turn.

The feed covers **only 7 featured models**. For the rest, context is model-card /
HuggingFace only (e.g. `mistral-large-3` = 262,144, confirmed both on its
[model card](https://docs.api.nvidia.com/nim/reference/mistralai-mistral-large-3-675b-instruct-2512)
and via the empirical probe below). It is unversioned and unsupported — **cache a local
copy** rather than fetching live.

**Empirical fallback** (when a model isn't in the feed): send `max_tokens: 50000000` and
parse the `max_model_len` from the 400 error. Works only on strict-validation (vLLM)
backends — Mistral models cough up `max_model_len=262144`; others silently clamp and
answer, so it's not universal.

---

## Rate limits & the credit system

**429 and 402 are different failures — this is the key to the GLM problem.**

| Code    | Means                       | Behaviour                                                                                                 | Fix                                                       |
| ------- | --------------------------- | --------------------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| **429** | rate / capacity limit       | **persists ~1 hour** (community), a penalty/burst model — not a clean 60s window; fires even below 40 RPM | backoff + `Retry-After` + **fail over to another model**  |
| **402** | inference credits exhausted | persistent until you top up; body `"Cloud credits expired - Please contact NVIDIA representatives"`       | business email (+4k credits) / "Request More" / self-host |

**The GLM 429-that-doesn't-clear-in-60s is a rate-limit cooldown, NOT credits.** Credit
exhaustion is a 402, not a 429. NVIDIA's free trial limits are not a textbook rolling
minute — community reverse-engineering converges on a **~1-hour penalty** after a
violation, plus undisclosed per-model capacity caps, and users report 429s below 40 RPM.
The GLM family is repeatedly named as 429-prone. NVIDIA explicitly **refuses to publish
per-model limits** ("We do not currently publish the limits for each model" — staff), so
"GLM throttles sooner than lighter models" is community-consistent but unverified.

**Credits (separate axis):** one-time trial pool — **1,000 on signup, up to 5,000** with a
business email (+ a 90-day AI Enterprise license) or the profile "Request More" flow. **No
documented refill cadence** (treat as non-recurring). Some 2026 third-party trackers claim
the credit caps were removed and the free tier is now rate-limit-only; NVIDIA has no dated
statement resolving this — the 1,000/5,000 + 402 record is the last staff-confirmed truth.

**Observability:** **no rate-limit or credit headers** on 200 responses (only `Nvcf-Reqid`
/ `Nvcf-Status`); 429s are often returned with **no body and no headers**. Remaining credit
balance is **dashboard-only**. So the only ground truth at runtime is the **status code**:
429 → cooldown/fail-over, 402 → out of credits.

### The underlying logic: TWO independent per-model limiters

Measured directly. GLM-5.2's 429 is **not** a global 40 RPM. It's two separate,
model-specific limiters with **opposite severities**:

| Limiter         | GLM-5.2 limit             | Exceed behaviour                                                                | Recovery                                    |
| --------------- | ------------------------- | ------------------------------------------------------------------------------- | ------------------------------------------- |
| **Concurrency** | **~6 in-flight**          | instant 429 on the _excess only_; the allowed ~6 succeed and the model stays up | **none** — retry the rejected requests      |
| **Rate**        | **~20 req / rolling 60s** | 429 **+ penalty-box lockout**                                                   | **~25 min of silence** (probing extends it) |

Evidence (each batch fired from a cleared rate window, so its 429s are pure concurrency):

| Test              | Model        | Load                           | Result                                                                   |
| ----------------- | ------------ | ------------------------------ | ------------------------------------------------------------------------ |
| concurrency batch | **GLM-5.2**  | 5 simultaneous                 | 5×200 (under cap)                                                        |
| concurrency batch | **GLM-5.2**  | 10 simultaneous                | **6×200, 4×429** → cap ≈ 6; model usable immediately after (200/200/200) |
| serial ramp       | **GLM-5.2**  | paced 20→30/min, concurrency 1 | **429 at ~21 in the trailing 60s** (20/min sustained clean)              |
| concurrency batch | qwen3.5-397b | 20 simultaneous                | 20×200 — no cap near 20                                                  |

**Key distinction:** the concurrency gate (~6) is **benign** — a soft admission limit; bounce
the excess, retry, done. The **rate cap is the punitive one** — cross it and you're locked out
~25 min. Both are far below the documented 40 RPM, and both are model-specific (qwen's
concurrency cap is ≥20; GLM's is ~6 because it's the popular model — "limits depend on model"
in practice).

**The rate cap is DYNAMIC and appears to DEGRADE under sustained use — it is not a fixed
number.** Measured on GLM-5.2 the same session: early on it sustained 20/min and tripped at
~21 in a rolling 60s; after a session of heavy use + several lockouts, it tripped at just
**13** in the rolling window at a 15/min pace. Same model, same method, ~35% lower. This
implies a **multi-window limiter**: a short rolling window (~20 when fresh) _plus_ a
longer-window / cumulative budget that tightens the effective short-term cap the more you
consume. It's why the behaviour feels "dynamic and strange," why forum users report "429 even
when barely using it" (depleted longer-window budget), and why NVIDIA publishes no number —
there isn't a stable one. **Do not tune to the ceiling; it moves and it punishes overshoot.**
Treat ~20/60s as an optimistic _fresh_ cap and operate well under it (~10-15/min) with
backoff. Heavy use makes the ceiling drop, so chasing max throughput is self-defeating.

**The longer-window budget is personal and slow — but recovers in tens of minutes, not a
day.** Tested: after ~316 GLM requests in one session (incl. a 250-request burst), a full
**30 minutes of total silence did NOT restore GLM** — but it _did_ recover by ~45-60 min.
Over the session the recovery time _lengthened_ (25 min early → ~45-60 min after heavy use)
and the cap _dropped_ (20 → 13), both tracking cumulative usage monotonically → a **per-key
cumulative budget** on a ~tens-of-minutes window (not global load-shedding; NVIDIA cites
"current overall traffic" too, but a global-only model wouldn't track _your own_ usage like
this). Bottom line: **the severe degradation is an artifact of heavy testing, not normal
use** — paced real use won't drain it; if you do, it clears in ~an hour, not a day.

### Per-model rate tiers (measured — the "40 RPM" is an unreached ceiling)

Serial 40/min test, rolling-60s count at the 429. **Every model tiers differently, and none
reach the documented 40:**

| Model                            | rate cap (~rolling-60s) | concurrency | agentic | reliability         |
| -------------------------------- | ----------------------- | ----------- | ------- | ------------------- |
| `qwen/qwen3.5-397b-a17b`         | **~33-35** (2 samples)  | ≥20         | 20      | ⚠️ ~11% HTTP 500s   |
| `moonshotai/kimi-k2.6`           | **~30**                 | untested    | 30      | ✅ clean            |
| `z-ai/glm-5.2`                   | ~20 fresh (degrades)    | ~6          | 43      | ✅ clean            |
| `mistralai/mistral-large-3-675b` | **~15**                 | high        | —       | ✅ fast (111 tok/s) |

Confirms the multi-tier hypothesis: rate caps are per-model policy, spanning ~15-35 here, all
**under** the documented "up to 40 RPM" — which is the account-tier _ceiling_, not a per-model
figure (qwen at ~35 is the closest any model gets; popular GLM is tiered lowest at ~20).
Throughput and rate-cap are **independent** (mistral-large is fastest but most rate-limited).
Caveat: absolute numbers may be depressed by session-wide cumulative usage; treat the
_ordering_ (qwen > kimi > GLM > mistral) as robust. **Design consequences:**

- **The pacer must be per-model** (GLM ~12/min, kimi ~22/min, qwen ~28/min, mistral ~10/min),
  not one global RPM.
- **kimi-k2.6 is the best fallback** — agentic 30 (double qwen's), rate ~30 (nearly qwen's),
  and clean (qwen throws ~1-in-9 HTTP 500s). Recommended default design: **GLM primary (paced)
  → kimi fallback on 429/cooldown.** qwen is the raw-rate champion but too weak-agentic and too
  flaky to be the smart fallback.

This explains the whole saga: a hard burst (e.g. 40 concurrent) trips the concurrency gate
_and_ blows 20/60s at once → instant 429s **and** a 25-min lockout. A gentle serial client
still hits the rate lockout past ~20/min. "429s below 40 RPM" in the forums = people hitting
one of these two sub-40 limits.

**Practical rule for GLM:** cap the proxy to **≤6 concurrent AND ≤~15 req/min**. Concurrency
limiting alone isn't enough (rate lockout); rate limiting alone isn't enough (concurrency
bounces) — but only the rate breach is costly. A `max_concurrent=6` + ~15/min token bucket
makes GLM essentially never hit the punitive lockout. (Prior art: NVIDIA forum thread 335755
independently reports "429 after ~20 requests/min" and multi-hour lockouts — anecdotal
corroboration; the per-model concurrency=6 / rate=20 split and the benign-vs-penalty
distinction appear to be undocumented elsewhere.)

### Measured 429 recovery & scope (2026-07-06 stress test)

Deliberately tripped GLM-5.2 and watched recovery, with `mistral-large-3` as a control:

- **The 429 body is `{"status":429,"title":"Too Many Requests"}` with no `Retry-After` and
  no rate-limit headers.** You get zero backoff guidance.
- **GLM recovered in ~22-27 min** (down at 20 min under active polling; back within ~5 min
  of going silent). Not the full hour community folklore suggests — at least at this abuse
  level. **Going quiet appears to help recovery** (weak evidence: active 45s-interval
  polling kept it down 20 min; silence let it recover). Treat continued probing during
  cooldown as counterproductive.
- **Throttles are PER-MODEL with independent, staggered recovery — not a single key-wide
  lock.** When GLM recovered, the control was _still_ 429 (it tripped ~8 min later and
  recovered later). So each model cools down on its own timer.
- **BUT multiple models can be throttled simultaneously.** Mid-incident, both GLM and the
  control were down at once — a hard burst on one model can drag others down for a window.
  So failover is real but **best-effort**: your fallback may or may not also be tripped.
- **No anonymous access.** Inference requires a valid key (401 with no header, 403 with a
  bogus key); only `GET /v1/models` is open. The limit is **key/account-scoped**, not
  IP-scoped — you can't sidestep a cooldown by dropping the key. A second account (different
  email) is a different quota.

**Consequence for design:** a GLM 429 gives you no `Retry-After`, can co-occur across
models, and clears in ~20-30 min if you stop hammering. So the mitigation stack is:
(1) **stay under both caps** — for GLM that's **≤6 concurrent AND ≤~15/min** (a serial client
at 30/min still hits the rate lockout; a 10-wide burst still bounces on the ~6 concurrency
gate); (2) on 429, **fail over** to
another model (best-effort — LiteLLM `cooldown_time` does this; Olla can't); (3) if the
fallback is also down, **go quiet and surface it** — make switching back to `ccl`/Claude
one keystroke rather than engineering heavier failover. `ccnim` is a free trial surface,
not infrastructure (see intro) — fail fast, don't over-harden.

---

## Proxy layer: Olla, and why it can't solve the 429 problem

Claude Code speaks the Anthropic Messages API; NIM's hosted gateway speaks
OpenAI-compatible only. A translation proxy (Olla) is **required** — see
[native endpoint](#the-native-anthropic-endpoint-self-hosted-only).

**Olla ([thushan/olla](https://github.com/thushan/olla)) cannot fail over on a 429.**
Confirmed from source:

- Retry/failover fires **only on connection-level errors** (refused/reset/timeout before a
  response). Any real HTTP response — including 429 — is treated as success and streamed
  straight back to Claude Code.
- Circuit breakers (5 consecutive transport failures / 3 failed probes) **never trip on
  429**; the endpoint stays "healthy," so priority-failover doesn't engage.
- No `Retry-After` handling on the proxy path, no 429 backoff.
- **No idle auto-shutdown** — Olla runs until killed (relevant to the watchdog plan item;
  it must be built externally).
- `model_aliases` _can_ map one alias to a list of models across endpoints and load-balance
  them, but that failover still only triggers on connection errors — **a GLM 429 will not
  push traffic to a fallback model.**

**Implication:** "on GLM 429, temporarily serve another model" must be built outside Olla.

Options:

1. **Wrapper-level retry** in `ccnim` — catch 429, flip model for the session. Crude
   (mid-session swap disrupts an agent loop).
2. **Replace Olla with LiteLLM proxy** — native 429 failover (`fallbacks` + `cooldown_time`
   that benches a rate-limited model), Anthropic↔OpenAI translation, **and** a model DB that
   knows context windows (`get_max_tokens`). Collapses translation + 429-failover +
   context-map into one tool. Trade-off: bigger dependency; re-verify its `reasoning_content`
   handling.
3. **Keep Olla + a tiny 429-aware sidecar** in front that rewrites the alias to a fallback
   with a cooldown.

Given GLM 429s happen in practice, option 2 (LiteLLM) is the strongest candidate — it turns
a GLM 429 into a transparent fallback (Kimi-K2.6 / Mistral-Large-3) and hands you context
windows for free.

---

## The native Anthropic endpoint (self-hosted only)

NVIDIA's docs describe a native Anthropic `/v1/messages` endpoint for Claude Code — but it
is a **vLLM passthrough that only exists on self-hosted NIM containers**. Confirmed:

- Empirically: every `/v1/messages` path variant 404s on `integrate.api.nvidia.com`.
- In docs: the endpoint is documented only in the self-hosted container reference; the
  hosted cloud API reference (`docs.api.nvidia.com`) lists no Anthropic endpoint.

**So on the free hosted tier the proxy is not optional.** If you ever self-host a NIM
container, the proxy becomes redundant — point Claude Code straight at the container.

---

## Other tools (GitHub landscape)

- **[musistudio/claude-code-router](https://github.com/musistudio/claude-code-router)**
  (~35k★) — mature, maps reasoning→thinking, but carries a NIM-breaking bug
  ([#1410](https://github.com/musistudio/claude-code-router/issues/1410)): unconditionally
  injects a `reasoning` param that **500s Kimi K2.6 and 400s Qwen**. Lesson for our config:
  only forward reasoning params when thinking is actually enabled.
- **[diyism/cc-nim](https://github.com/diyism/cc-nim)** — tiny, NIM-native, per-tier
  GLM/Kimi/MiniMax mapping + reasoning normalization. Closest conceptual twin to `ccnim`.
- **[zhangrr/claude-nvidia-proxy](https://github.com/zhangrr/claude-nvidia-proxy)** (Go) —
  NIM-native but does **not** convert reasoning → prone to the empty-UI symptom.

---

## Sources

- Model list: `curl https://integrate.api.nvidia.com/v1/models` (unauthenticated).
- Intelligence/coding/agentic indices, native context: Artificial Analysis
  (`artificialanalysis.ai/models`, embedded dataset).
- Served context + max-output: `assets.ngc.nvidia.com/products/api-catalog/featured-models.json`.
- TPS / TTFT / tool-call / reasoning-leak: local probe harness (scratchpad `nim_probe.py`),
  measured against `integrate.api.nvidia.com/v1/chat/completions`, 2026-07-06.
- Rate limits: [NVIDIA developer forum](https://forums.developer.nvidia.com/t/clarity-on-nim-api-free-tier-rate-limit-increases/369624).
- Olla behaviour: [github.com/thushan/olla](https://github.com/thushan/olla) source + docs.
- Native endpoint: [NVIDIA NIM Claude Code integration](https://docs.nvidia.com/nim/large-language-models/latest/ai-assistant-integrations/claude-code.html)
  (self-hosted).
