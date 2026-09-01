# NVIDIA NIM free models for Claude Code (`ccnim`)

How the free hosted NVIDIA NIM models actually behave when driven by Claude Code
through the Olla proxy. Every number below is **measured against the live hosted
API** (`integrate.api.nvidia.com/v1`) or pulled from a cited primary source — not
copied from a benchmark leaderboard or an LLM's opinion.

- **Run 1:** 2026-07-06, single-sample per model, free tier, from Ottawa.
- **Run 2:** 2026-08-08, N=5 per model with medians, free tier, from **Paris via
  Proton VPN**. TLS connect stayed at 32-80 ms throughout, so the path is not the
  story, but absolute TTFT is not strictly comparable across runs.
- **Why this exists:** an earlier model ranking was taken from ChatGPT's tier list,
  which ranked models by reputation, not data. It put `gpt-oss-120b` at #1 — the
  slowest, weakest-agentic model on the list. This doc replaces that with hard data.

> **Set expectations first: this is a trial surface, not an API provider.** NVIDIA
> positions build.nvidia.com as a free "trial experience... for experimentation,
> development, testing and research" — a demo funnel toward self-hosted NIM containers and
> paid DGX Cloud. There is no SLA and the reliability will not improve, because reliability
> isn't the product. `ccnim` is therefore a "free ride when it's up," never load-bearing.
> Don't over-invest in hardening it; the reliable paths are `ccl` (local llama.cpp),
> self-host, or real Claude. Design `ccnim` to **fail fast and hand off**, not to paper
> over a demo endpoint's limits.
>
> **Run 2 is the evidence for that thesis, not a footnote to it.** In four and a half
> weeks the catalogue lost five of the doc's ten ranked models, the recommended default
> became unusable, and the recommended fallback stopped being entitled to this account.
> Treat every model id here as expiring.

---

## TL;DR — what to actually run

> **Run 3, 2026-08-29.** `inkling` and `glm-5.2` are gone; `kimi-k3` and
> `deepseek-v4-pro` became callable. Default moved to **`moonshotai/kimi-k3`**.
> Run 2's table below is kept for the mechanics, which still hold. See
> [run 3](#run-3-2026-08-29--payload-size-changes-the-ranking).

**Default: `moonshotai/kimi-k3`.** 2.5s on a 92 KB payload, 6.6s wall end to end through
Olla. Emits into `reasoning_content`, which Olla maps, so it renders correctly.

**Fallback: `deepseek-ai/deepseek-v4-flash-0731`.** 18.0s on the same payload. Was run 2's
fallback at 21 tok/s and remains serviceable, though it degraded to 529s on some
small-prompt samples in run 3.

**Do not default to `deepseek-ai/deepseek-v4-pro-0813`** despite it being the strongest
model here and the only one emitting pure `content`: **146.4s** on a 92 KB payload. Fine
for one careful question, unusable in an agent loop.

**Avoid on the free hosted tier:**

- `z-ai/glm-5.2` — **was** the default, now takes **91s median to first token** (max 120s).
  Generation is fast once it starts, so this is queueing, not throughput. Unusable in an
  agent loop.
- `minimaxai/minimax-m3` — fast (71 tok/s) and clean, but rate-brittle: 429'd on 3 of 5
  serial requests spaced 4s apart.
- `nvidia/nemotron-3-ultra-550b-a55b` — 54 tok/s but emits 38 chars of `content` against
  183 of `reasoning_content`. Blank-UI risk if a proxy ever stops mapping the field.
- `openai/gpt-oss-120b` — still all-reasoning, no content, and wildly variable (0.6 to
  100s+ observed in the same session).

**Gone entirely** (see [catalogue churn](#catalogue-churn-and-how-to-read-a-missing-model)):
every Qwen model, both Mistral Large/Medium 3 entries, and `kimi-k2.6` is listed but not
callable by this account. As of run 3, add `thinkingmachines/inkling` (410, EOL
2026-08-25) and `z-ai/glm-5.2` (delisted).

---

## Run 3 (2026-08-29) — payload size changes the ranking

**The headline is a methodology error, not a model.** Runs 1 and 2 ranked models on short
prompts. Claude Code's real request body is **~113 KB** (measured off Olla:
`content_length=113543`). Re-measured at 92 KB, the ordering inverts:

| Model                                | 92 KB payload | short prompt (N=5, paced)       | verdict             |
| ------------------------------------ | ------------- | ------------------------------- | ------------------- |
| `moonshotai/kimi-k3`                 | **2.5s**      | 4/5, 5.4s TTFT                  | ✅ **default**      |
| `deepseek-ai/deepseek-v4-flash-0731` | 18.0s         | 0/5 content, 5/5 reasoning-only | ✅ fallback         |
| `deepseek-ai/deepseek-v4-pro-0813`   | **146.4s**    | 5/5, pure content, 8.8s TTFT    | ❌ too slow to loop |

A short-prompt harness ranked `pro` first — 5/5 content-bearing, zero 429s, the only model
needing no `reasoning_content` mapping. All true, and all irrelevant at 60× the latency.
**Rank on a realistic payload or do not rank.**

`pro`'s "pure content" edge is also worth less than it looks: Olla maps `reasoning_content`
already, which is why kimi and flash render fine despite emitting nothing into `content`.

**Catalogue churn since run 2:** `kimi-k3` was a plain 404 (unknown to the gateway) and
`deepseek-v4-pro` was unentitled; both are callable now. Entitlement moves in both
directions, so re-probe rather than trusting a prior run.

### The `deprecation:` header predicts the next EOL

NIM sends an RFC-8594 `deprecation` header carrying the retirement timestamp, on both 200s
and 429s, and **only** for models scheduled to die:

```
$ curl -sD- .../chat/completions -d '{"model":"minimaxai/minimax-m3",...}' | rg -i deprec
deprecation: 2026-09-09T09:00:00Z
```

Nothing else in the shortlist carries one. This is the signal that would have caught
`inkling` before it 410'd mid-session — one 1-token call per model reads it.

### `/v1/models` still has no context figure, and the feed is now three weeks stale

The `featured-models.json` carousel feed is **unchanged since run 2 (2026-08-08)**: still
lists `z-ai/glm-5.2` (delisted) and the pre-EOL `deepseek-v4-pro`, and still has no entry
for `kimi-k3` or `deepseek-v4-flash-0731`. Treat it as abandoned.

Run 2's empirical fallback (`max_tokens: 50000000`, parse `max_model_len` from the 400) no
longer works either — the current backend returns an empty body instead of a validation
error, so there is now **no** programmatic context source for the default model.

### Olla's default read timeout is 30s and looks like a backend outage

A slow model on a real payload trips it, and the error blames the wrong component:

```
proxy request failed: network timeout after 30.1s - unable to connect to LLM backend
```

The backend was reachable and working. `server.read_timeout` (default 30s) is the cause;
raised to `5m` in `~/.config/olla/config.yaml`, with `write_timeout` left at `0s` because
streaming breaks otherwise. This matters much less with a fast default, but it turns a
6-second failure into a legible one.

---

## Catalogue churn, and how to read a missing model

The catalogue holds ~100 ids. Five of the ten models ranked in run 1 are no longer
usable. NVIDIA distinguishes the reasons, and the distinction is diagnostic:

| Response                                                              | Meaning                                      | Seen on                                                            |
| --------------------------------------------------------------------- | -------------------------------------------- | ------------------------------------------------------------------ |
| plain `404 page not found`                                            | id unknown to the gateway                    | `mistral-large-3-675b`, `mistral-medium-3.5`, `moonshotai/kimi-k3` |
| structured 404, `"Function '<uuid>': Not found for account '<acct>'"` | routing exists, **your key is not entitled** | `moonshotai/kimi-k2.6`                                             |
| `410 Gone` + EOL timestamp                                            | deliberately retired                         | see table below                                                    |

**`kimi-k2.6` is the important case: it is still listed in `/v1/models` and still
404s on inference.** The list endpoint is a global catalogue, not an account view, so
**listing is not an entitlement check**. Another key may well serve it.

Retirements, with the dates NVIDIA returns in the 410 body:

| Model                           | End of life          |
| ------------------------------- | -------------------- |
| `moonshotai/kimi-k2-instruct`   | 2026-05-12           |
| `qwen/qwen3.5-397b-a17b`        | 2026-07-27           |
| `deepseek-ai/deepseek-v4-pro`   | 2026-08-07T09:00:00Z |
| `deepseek-ai/deepseek-v4-flash` | 2026-08-07T09:00:00Z |

Both DeepSeek previews died at the same instant, a coordinated cleanup after DeepSeek
shipped the official V4-Flash on 2026-07-31. No `v4-pro` replacement is listed yet;
DeepSeek says the official Pro "will follow soon," so expect that slot to refill.

**Do not use the `created` field to date a model.** `/v1/models` returns
`735790403` (1993-04-26) for every entry — a constant placeholder. The 410 EOL
timestamp is the only real date the API gives you.

New arrivals since run 1: `thinkingmachines/inkling`, `deepseek-ai/deepseek-v4-flash-0731`,
`stepfun-ai/step-3.7-flash`, `poolside/laguna-xs-2.1`, `google/diffusiongemma-26b-a4b-it`,
`nvidia/cosmos-reason2-8b`, `nvidia/ising-calibration-1.5-31b`.

---

## Model ranking (measured 2026-08-08, N=5, medians)

**Superseded by run 3 for the choice of default.** Kept because the mechanics (single
samples are noise, the GLM queue collapse) still hold. `inkling` was run 2's default and
has been 410 since 2026-08-25.

Sequential per model, 5 samples each, 250 max tokens, one tool defined. `ok` counts
samples that produced any output. `leak` counts samples emitting `reasoning_content`.

| Model                                | ok      | TTFT med  | tok/s med | tok/s range | tool | leak | Claude Code verdict                                      |
| ------------------------------------ | ------- | --------- | --------- | ----------- | ---- | ---- | -------------------------------------------------------- |
| **`thinkingmachines/inkling`**       | **5/5** | **0.5s**  | **73.6**  | 27-92       | 5/5  | 5/5  | ✅ run 2 default (now 410) — leaks but emits content too |
| `stepfun-ai/step-3.7-flash`          | 3/5     | 0.6s      | 92.3      | 40-93       | 3/3  | 3/3  | ⚠️ fastest measured, but 2/5 timed out                   |
| `nvidia/nemotron-3-ultra-550b-a55b`  | 5/5     | 0.7s      | 54.1      | 40-59       | 5/5  | 5/5  | ⚠️ 38 chars content vs 183 reasoning                     |
| `deepseek-ai/deepseek-v4-flash-0731` | 5/5     | 0.6s      | 21.1      | 5-48        | 5/5  | 0/5  | ✅ **fallback** — clean content, reliable                |
| `minimaxai/minimax-m3`               | 2/5     | 0.5s      | 71.2      | 68-75       | 2/2  | 0/5  | ⚠️ fast and clean, but 3×429                             |
| `z-ai/glm-5.2`                       | 3/3     | **91.1s** | 7.8       | 8-44        | 3/3  | 0/3  | ❌ ~90s TTFT — dead-air symptom                          |

**The GLM collapse is the headline.** Run 1 measured 1.0s TTFT and 35 tok/s and made it
the default. Run 2 measures 91s median, 120s max, over three samples that all returned 200. Generation once started is ~0.9s for 200 chars, so the model is fine and the queue
is not. Single-sample probing hides this: my first three attempts timed out at 60s and
150s and read as "the model is down."

**Single samples are noise.** `minimaxai/minimax-m3` measured 1.7s generation on one
run and 19s on the next; `stepfun-ai/step-3.7-flash` timed out at 240s once and returned
134 tok/s two minutes later. Run 1's whole table is single-sample. Trust the ordering,
not the values.

---

## Claude Code compatibility (verified end to end, not just by curl)

Driven through Olla with the real `claude` CLI, not a probe script:

| Model                                | Task                                | Result                                |
| ------------------------------------ | ----------------------------------- | ------------------------------------- |
| `thinkingmachines/inkling`           | trivial prompt                      | correct, **4.6s**                     |
| `thinkingmachines/inkling`           | Read a file, report contents        | correct, **12.2s**                    |
| `deepseek-ai/deepseek-v4-flash-0731` | Read a file, report contents        | correct, **9.7s**                     |
| `deepseek-ai/deepseek-v4-flash-0731` | Glob → Read → reason about the code | correct, cited `config.js:1`, **30s** |
| `ccnim` after the 2026-08-08 fixes   | trivial prompt                      | correct, **9.3s**                     |
| `ccl` (local GLM-4.7-Flash, warm)    | trivial prompt                      | correct, **4m29s**                    |

`ccl`'s 4m29s is the Claude Code system-prompt prefill on an M4 Pro, not a fault. It is
the reason `ccnim` exists at all.

**New friction:** Claude Code 2.1.226 warns on every unrecognized model id and assumes a
200k context window. Append `[1m]` to the model name, set `CLAUDE_CODE_MAX_CONTEXT_TOKENS`,
or map it in `modelOverrides` if the real window matters.

### `reasoning_content` leakage

Run 1 called mapping `reasoning_content` → Anthropic thinking "the single most important
proxy fix." **It is already fixed upstream in Olla** (`response.go:191`,
`streaming.go:248-281`), which is why inkling and nemotron render correctly today despite
leaking. Nothing to do here.

The residual risk is `nemotron-3-ultra`, which emits far more reasoning than content
(183 vs 38 chars). If a future proxy path drops the field, that model goes blank first.

---

## Error taxonomy (expanded in run 2)

Run 1 said the status code is the only ground truth. That is no longer complete.

| Signal                                             | Meaning                                                              | Failover-visible?            |
| -------------------------------------------------- | -------------------------------------------------------------------- | ---------------------------- |
| `429` `{"status":429,"title":"Too Many Requests"}` | rate or concurrency limit, no `Retry-After`                          | yes                          |
| `402`                                              | inference credits exhausted                                          | yes                          |
| `410` + EOL timestamp                              | model retired                                                        | yes                          |
| `404` structured, "Not found for account"          | not entitled                                                         | yes                          |
| **`529` `Service temporarily overloaded`**         | transient capacity, distinct from 429                                | **only if you check for it** |
| **`200` + in-stream `data: {"error":{...}}`**      | `ResourceExhausted: Worker local total request limit reached (N/32)` | **NO**                       |

**The in-stream error is the dangerous one.** The HTTP status is 200, the SSE stream
opens normally, and the failure arrives as an error object inside a `data:` frame:

```
data: {"error":{"message":"ResourceExhausted: Worker local total request limit reached (203/32)","type":"internal_server_error","code":500}}
```

Any 429-based failover — including the Olla PoC below — is blind to this. So is a naive
probe: my first harness scored these as "HTTP 200, empty response" until I fixed the
parser, and run 1's `qwen ~11% HTTP 500s` line was probably partly this. Seen on
`poolside/laguna-xs-2.1` and `nvidia/nemotron-3-ultra-550b-a55b`.

**New observability:** responses now carry `nvext.scheduler_snapshot` with
`num_running_reqs` and `num_waiting_reqs`. Run 1 concluded there were no rate-limit
signals at all; there is now a queue-depth one, which is the closest thing to a
back-pressure hint NVIDIA exposes.

---

## Thinking and `reasoning_effort`

**The parameter is real and the enum is validated.** A bogus value 400s with the full
list: `none`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`.

**Whether it does anything is per model.** `extra_body` is rejected outright
(`Unsupported parameter(s): 'extra_body'`), so pass parameters at the top level.

`thinkingmachines/inkling` **honours it, monotonically** (N=4, non-overlapping ranges):

| effort    | completion tokens (med) | reasoning chars (med) | range   |
| --------- | ----------------------- | --------------------- | ------- |
| `minimal` | 130                     | 121                   | 112-153 |
| `medium`  | 254                     | 358                   | 327-453 |
| `max`     | 324                     | 594                   | 466-721 |

`deepseek-ai/deepseek-v4-flash-0731` **does not.** With thinking off, every effort level
produces zero reasoning. With thinking on, `minimal` produced _more_ reasoning than `max`
(median 1316 vs 599 chars, N=5), so the ordering is inverted rather than merely noisy.

**DeepSeek's actual lever is `chat_template_kwargs: {"thinking": true}`**, a non-standard
NIM parameter: it moves completion tokens from ~146 to ~496 and reasoning from 0 to
~1300 chars. This is independently corroborated by the `pi-nvidia-nim` extension, whose
README states the same thing and maps it per model.

**None of this is reachable from `ccnim` today.** The strings `chat_template_kwargs` and
`reasoning_effort` do not appear anywhere in Olla's source. Claude Code's thinking request
does arrive and `detectRequestFeatures` (`handler_translation.go:1087-1090`) sets an
`extendedThinking` flag from it, but that flag only selects eligible endpoints and is
never written to the outbound request. Closing this would be a small Olla patch, and
unlike the 429 PoC it does not collide with the upstream refactor described below.

---

## Rate limits and the credit system

Run 1's mechanics still hold and remain the best explanation; run 2's numbers are lower
in absolute terms. **Treat the ordering and the shape as durable, the numbers as not.**

**429 and 402 are different failures.**

| Code    | Means                       | Behaviour                                                                                                 | Fix                                                       |
| ------- | --------------------------- | --------------------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| **429** | rate / capacity limit       | **persists ~1 hour** (community), a penalty/burst model — not a clean 60s window; fires even below 40 RPM | backoff + fail over to another model                      |
| **402** | inference credits exhausted | persistent until you top up; body `"Cloud credits expired - Please contact NVIDIA representatives"`       | business email (+4k credits) / "Request More" / self-host |

**Credits (separate axis):** one-time trial pool — 1,000 on signup, up to 5,000 with a
business email. **No documented refill cadence.** Some 2026 third-party trackers claim the
caps were removed and the free tier is now rate-limit-only; NVIDIA has no dated statement
resolving this. Remaining balance is dashboard-only.

### TWO independent per-model limiters

Measured in run 1 on GLM-5.2, and the shape re-confirmed in run 2 on inkling:

| Limiter         | Exceed behaviour                                                                      | Recovery                               |
| --------------- | ------------------------------------------------------------------------------------- | -------------------------------------- |
| **Concurrency** | instant 429 on the _excess only_; the allowed requests succeed and the model stays up | **none** — retry the rejected requests |
| **Rate**        | 429 **+ penalty-box lockout**                                                         | tens of minutes; probing extends it    |

The concurrency gate is **benign**; the rate cap is **punitive**. Only the rate breach costs you.

**Run 2 concurrency measurement:** `thinkingmachines/inkling` at 10 simultaneous returned
**6 ok, 4×429 in 4.1s** — a concurrency cap of ~6, the same figure run 1 measured for
GLM-5.2. This looks like a per-model default rather than a GLM-specific popularity penalty.

**Run 2 rate measurement:** `minimaxai/minimax-m3` 429'd on **3 of 5 serial requests**
spaced 4s apart (~13/min equivalent), well under run 1's ~20/min GLM figure and far under
the documented 40 RPM. Consistent with run 1's finding that the effective cap **degrades
with cumulative session usage**.

**Recovery is faster than run 1 suggested.** minimax was serving again within ~10 minutes
of its lockout, against run 1's measured 22-27 min for GLM and the ~45-60 min it reached
after heavy abuse. Our cumulative usage in run 2 was much lower, which supports the
per-key cumulative-budget model rather than contradicting it.

**Run 2 deliberately did not re-run the punitive serial ramp.** It costs a lockout on
whichever model it targets, and run 1 already established the mechanism. The numbers above
are what fell out of ordinary benchmarking, which makes them a realistic floor.

**Per-model rate tiers from run 1** (`qwen ~33-35 > kimi ~30 > glm ~20 > mistral ~15`)
are now largely historical: qwen, kimi and mistral-large are all gone or unentitled. The
surviving lesson is that **the pacer must be per-model**, and that no model reaches the
documented 40 RPM.

**Practical rule:** cap the proxy to **≤6 concurrent** and pace well under the observed
rate. Concurrency limiting alone isn't enough (rate lockout); rate limiting alone isn't
enough (concurrency bounces). Only the rate breach is costly.

---

## Proxy layer: Olla

Claude Code speaks the Anthropic Messages API; NIM's hosted gateway speaks
OpenAI-compatible only. A translation proxy is **required** — see
[native endpoint](#the-native-anthropic-endpoint-self-hosted-only).

**What Olla already does right:** maps `reasoning_content` into Anthropic thinking blocks,
which retires run 1's top-priority fix.

**What it still can't do:** fail over on a 429 (retry fires only on connection-level
errors; a real HTTP response, 429 included, is streamed straight back), and pass any
thinking parameter through to NIM.

**And it is now blind to the in-stream 200 errors** documented above, which no amount of
429 handling would catch.

### PoC: 429 failover, and its rebase debt

Upstream feature request: [thushan/olla#193](https://github.com/thushan/olla/issues/193).
Patch at `docs/olla-429-failover.poc.patch` (5 files, +157/-21). Working copy in the fork
**`~/Developer/olla`** (SeanLF/olla), branch `feature/429-alias-model-failover`. Adds an
inline model-failover loop: on a 429, rewrite the request body's `model` to the next model
in the alias chain and re-dispatch to the same endpoint. Verified end to end against a
mock backend.

**Status as of 2026-08-08:** issue #193 is still **open with no maintainer reply** since
our own follow-up on 2026-07-26. Upstream's latest release is still v0.0.28 (2026-06-14),
but `main` is **324 commits ahead of our branch point**, and several land directly on the
code the PoC patches: a shared circuit-breaker state machine extracted into
`internal/adapter/resilience`, and the retry package's response-started tracker now gating
proxy error writes. **This needs a real rebase, not a fast-forward.**

Given no maintainer steer in six weeks and a growing rebase cost, the honest options are
to let the PoC lapse, or to sidestep the proxy entirely (next section).

---

## Harness choice: Claude Code vs pi vs codex

Measured 2026-08-08. The proxy requirement is a Claude Code problem, not a NIM problem.

|                 | NIM (remote)                               | llama-server (local)                       |
| --------------- | ------------------------------------------ | ------------------------------------------ |
| **Claude Code** | Olla required; works; thinking unreachable | direct via `/v1/messages`; `ccl` proves it |
| **pi**          | **direct**, extension handles thinking     | direct                                     |
| **codex**       | **impossible**                             | direct; verified                           |

**pi speaks Chat Completions natively.** Custom providers go in `~/.pi/agent/models.json`
with `"api": "openai-completions"` and a `baseUrl`, so NIM needs no translation layer, and
the `model_aliases` table disappears too — that exists only because Claude Code subagents
demand `claude-opus-4-8` and Olla 404s them. [xRyul/pi-nvidia-nim](https://github.com/xRyul/pi-nvidia-nim)
(active, 2026-07-20, 44★) already injects `chat_template_kwargs` per model via an
`onPayload` hook, which is exactly the gap in Olla. pi-mono is healthy (85.6k★, pushed
2026-08-08). **Not yet installed or run here — the config shape is from docs.**

**codex cannot reach NIM, for two independent reasons.** codex 0.147.0 hard-rejects
`wire_api = "chat"` at config load ("no longer supported"), and NIM has no Responses API
(`/v1/responses` and `/responses` both 404 while `/v1/chat/completions` 400s on a bad
body). Set `wire_api = "responses"` and codex retries the 404 five times with backoff and
then hangs rather than erroring. Bridging it needs a Responses↔Chat gateway, which is
more glue than Olla, not less.

**codex against `ccl` does work:** `CODEX_LOCAL_OK` in 26s / 7,633 tokens, because
`llama-server` serves **all three** protocols — `/v1/messages`, `/v1/chat/completions`
and `/v1/responses` all return 200 on the same port.

**`llama-server` cannot front NIM.** Its router mode (`--models-dir`, `--models-preset`,
`--models-max`) spawns **child `llama-server` processes on ephemeral 127.0.0.1 ports**,
each loading a local GGUF; it routes by model name to those children. No flag accepts an
upstream inference endpoint (`--model-url` downloads a GGUF; `--api-key` authenticates
clients inbound). Translation without remote routing, where Olla is remote routing without
weights. They are complementary, not substitutable.

**One privacy note:** codex contacted `https://chatgpt.com/backend-api/plugins/featured`
on startup with a purely custom provider and no login. The Olla config carries an
"only ever connects to integrate.api.nvidia.com" egress audit; routing through codex
would break that property.

---

## The native Anthropic endpoint (self-hosted only)

NVIDIA's docs describe a native Anthropic `/v1/messages` endpoint for Claude Code — but it
is a **vLLM passthrough that only exists on self-hosted NIM containers**. Confirmed
empirically (every `/v1/messages` path variant 404s on `integrate.api.nvidia.com`) and in
docs (the hosted cloud API reference lists no Anthropic endpoint).

**So on the free hosted tier the proxy is not optional** for Claude Code. If you ever
self-host a NIM container, point Claude Code straight at it.

---

## Context windows & output caps

**There is no supported NVIDIA API for context window.** `/v1/models` returns only `id`,
`object`, `created` (a placeholder), `owned_by`.

The one programmatic source is an undocumented feed behind the build.nvidia.com carousel:

```
https://assets.ngc.nvidia.com/products/api-catalog/featured-models.json
```

| Model                               | served context | max output |
| ----------------------------------- | -------------- | ---------- |
| `nvidia/nemotron-3-ultra-550b-a55b` | 1,048,576      | 8,192      |
| `nvidia/nemotron-3-super-120b-a12b` | 1,000,000      | 8,192      |
| `z-ai/glm-5.2`                      | 202,752        | 8,192      |
| `minimaxai/minimax-m3`              | 196,608        | 8,192      |
| `deepseek-ai/deepseek-v4-pro`       | 262,144        | 16,384     |

**The feed is stale as of 2026-08-08:** it still lists `deepseek-v4-pro`, which was
EOL'd on 2026-08-07, and no longer carries kimi or qwen. It has **no entry for inkling or
`deepseek-v4-flash-0731`**, so the two recommended models have no programmatic context
figure at all.

Standing gotchas: GLM-5.2 serves ~198k, not the 1M its native spec claims, and **output is
capped at 8,192 tokens** for most models (16k for deepseek/qwen). That cap is a real
constraint on large multi-file edits.

**Empirical fallback, no longer working as of run 3 (2026-08-29):** sending
`max_tokens: 50000000` used to return a 400 carrying `max_model_len` on strict-validation
(vLLM) backends. The current backend returns an empty body instead, so there is no
programmatic context source for the default model at all.

---

## `ccnim` defects found and fixed (2026-08-08)

1. **Stale 1Password item id.** `op_ref` pointed at an item that no longer existed; the
   script reported "run 'op signin' first," which is the wrong cause and cost real
   debugging time. Repointed at `c6x3xko43h7eibqpibtz7ou5uq` ("nvidia NIM API key"), with
   a comment naming the title so a future dead id is recoverable, and an honest error.
2. **Default model unusable.** Default was `z-ai/glm-5.2` at ~91s TTFT. Moved to
   `thinkingmachines/inkling` on 2026-08-08, then to `moonshotai/kimi-k3` in run 3 once
   inkling hit EOL. Current shortcuts are in `bin/ccnim`.

Verified after the fix: `ccnim -p` returns in 9.3s and correctly repoints Olla's aliases.

---

## Other tools (GitHub landscape)

- **[musistudio/claude-code-router](https://github.com/musistudio/claude-code-router)**
  (~35k★) — mature, maps reasoning→thinking, but carries a NIM-breaking bug
  ([#1410](https://github.com/musistudio/claude-code-router/issues/1410)): unconditionally
  injects a `reasoning` param that 500s Kimi and 400s Qwen. Lesson: only forward reasoning
  params when thinking is actually enabled.
- **[xRyul/pi-nvidia-nim](https://github.com/xRyul/pi-nvidia-nim)** — NIM provider for pi;
  the only tool found that handles NIM's `chat_template_kwargs` thinking quirk per model.
- **[diyism/cc-nim](https://github.com/diyism/cc-nim)** — tiny, NIM-native, per-tier
  mapping + reasoning normalization. Closest conceptual twin to `ccnim`.
- **[zhangrr/claude-nvidia-proxy](https://github.com/zhangrr/claude-nvidia-proxy)** (Go) —
  NIM-native but does not convert reasoning → prone to the empty-UI symptom.

---

## Sources

- Model list, EOL dates, error taxonomy, `nvext.scheduler_snapshot`: direct probes against
  `integrate.api.nvidia.com/v1`, 2026-07-06 and 2026-08-08.
- TPS / TTFT / tool-call / reasoning-leak / effort grid: local probe harness (N=5 medians),
  negative-controlled with a bogus key (403) and a bogus model id (404) before use.
- Intelligence/coding/agentic indices (run 1 only): Artificial Analysis.
- Served context + max-output: `assets.ngc.nvidia.com/products/api-catalog/featured-models.json`.
- Rate limits: [NVIDIA developer forum](https://forums.developer.nvidia.com/t/clarity-on-nim-api-free-tier-rate-limit-increases/369624).
- Olla behaviour: [github.com/thushan/olla](https://github.com/thushan/olla) source, read at
  `main` 2026-08-08.
- Kimi K3 on NIM: [availability request + NVIDIA reply](https://forums.developer.nvidia.com/t/kimi-k3-availability-request-on-nvidia-nim/378409)
  (2026-07-30: "The build team is constantly trying to bring the latest updates. Stay tuned!" —
  no commitment). [Dynamo self-host recipe](https://docs.nvidia.com/dynamo/dev/recipes/kimi-k3) exists,
  which points at the self-host funnel rather than the hosted tier.
- DeepSeek V4-Flash official release: [Caixin](https://www.caixinglobal.com/2026-08-01/deepseek-releases-official-v4-flash-model-as-chinas-ai-race-intensifies-102470292.html),
  [model card](https://huggingface.co/deepseek-ai/DeepSeek-V4-Flash-0731). Vendor-reported agent
  benchmarks (beats V4-Pro-Preview on all nine) had **no independent reproduction as of
  2026-08-03** and the DeepSWE figure uses DeepSeek's own unreleased harness.
- pi provider config: [pi models docs](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/models.md),
  [custom-provider docs](https://github.com/badlogic/pi-mono/blob/HEAD/packages/coding-agent/docs/custom-provider.md).
- codex `wire_api` removal: codex 0.147.0 config-load error, pointing at
  [openai/codex#7782](https://github.com/openai/codex/discussions/7782).
