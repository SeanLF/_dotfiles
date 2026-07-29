---
title: Match the subagent model to the work and give every one a stop condition, or mechanical tasks quietly cost reasoning-model money
date: 2026-07-25
category: best-practices
module: subagent delegation
problem_type: best_practice
severity: high
applies_when:
  - You are about to dispatch a subagent for research, counting, classification or a build matrix
  - You have dispatched several agents in one session without setting an explicit model
  - An agent reports it worked around a broken or rate-limited tool
  - A long session is producing good results and you have not looked at what they cost
tags: [subagents, delegation, cost, tokens, research, tooling]
---

## The lesson

Two dials exist on every subagent dispatch and both are easy to forget: **which model
runs it**, and **when it should give up**. Leaving the first at the session default sends
mechanical work to a reasoning model. Leaving the second unset lets an agent improvise
expensively around a tool that is simply unavailable.

## What happened

One session dispatched ~15 subagents. Every one used the default agent type, inheriting
the session's reasoning model; the `model` parameter was never set once. Measured from the
returned usage figures: **~2.3 million subagent tokens.**

Roughly half was justified — adversarial code reviews that found a symlink-destroying
regression, a test that asserted nothing, and a remotely-triggerable amplification bug.
That is reasoning work and it paid for itself.

The other half was read-and-summarise: counting and classifying an issue tracker, walking
commit history, surveying libraries, running build matrices, fetching web pages. All of it
would have run on a small model at low effort.

The clearest single failure: one agent's `WebSearch` was quota-exhausted **on its first
call**. Instead of reporting that and stopping, it improvised by fetching search-engine
HTML directly — DuckDuckGo CAPTCHA'd, Bing returned unrelated pages, Google served a
consent wall, SEC.gov 403'd. **64 tool calls and ~67,000 tokens produced two usable
facts.** A stop condition would have returned "search is unavailable" in one call, and
would also have prevented the two later agents dispatched into the same dead quota.

## Guidance

- Set `model` explicitly on every dispatch. Reasoning model for judgement — review,
  design critique, debugging. Small model at low effort for retrieval, counting,
  classification, formatting, running commands and reporting output.
- Never a small model at high effort; that is the worst square of the grid.
- Write the stop condition into the prompt: _"If &lt;capability&gt; is unavailable, stop and
  report that rather than working around it."_ Absence of a capability is a finding, not
  an obstacle to route around.
- Prefer naming primary sources over asking an agent to search. In the case above the only
  reliable channels were a direct API and specific known pages; the searching was what
  cost the tokens.
- When one agent reports a broken shared capability, treat it as session-wide until proven
  otherwise, and stop dispatching work that depends on it.
- Read the usage figures in agent results as they arrive. They are visible, and nobody
  looks until the bill is the story.

## Generalisation

The shape is **an unset default that silently upgrades the cost of every instance**.
It applies beyond agents: a retry policy with no cap, a log level left at debug, an
instance type inherited from a template. The tell is that nothing fails — output is fine,
so nothing prompts a review — and cost accrues in a dimension nobody is watching.

Corollary: an agent that reports "the tool was broken so I worked around it" has usually
made things worse. Reward the one that stops.

## Related

- [[a-passing-test-may-be-asserting-nothing]]
- [[a-cleaner-design-can-measure-worse-than-the-patch-it-replaces]]
