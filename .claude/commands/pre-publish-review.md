# Pre-Publish Editorial Review

## Setup

1. Identify which blog post to review. If not specified, find the most recently modified `.md` file in `~/Developer/seanfloyd.dev/views/blog/`.
2. Read all existing published blog posts for voice, format, and quality baseline.
3. Read `~/.claude/writing-style.md` for the author's voice guide.
4. Read `~/.claude/CLAUDE.md` for engineering philosophy.
5. Check `~/Developer/seanfloyd.dev/.claude/tasks/` for any brainstorm notes or source material related to this post.

## Review Chain

Run these reviews in parallel using subagents. Each should produce specific, actionable feedback - not generic praise. Flag only issues worth fixing.

### 1. Technical Accuracy

- Are all claims verifiable?
- Are links correct and pointing to public repos?
- Is anything stated as fact that's actually an assumption?
- Do cross-references to other posts match what those posts actually say?
- Are there claims about AI capabilities that could age badly?

### 2. Voice & Style Audit

- Check the article against every rule in `~/.claude/writing-style.md`
- Check for em dashes (AI tell), filler words, LinkedIn energy, false enthusiasm
- Check for hedging chains
- Does it sound like the same person who wrote the other posts?
- Is the humour dry and earned, or forced?
- Canadian spelling throughout?

### 3. Career Positioning Review

- Does this help or hurt the author's positioning as a staff-level engineer?
- Could a hiring manager read this and think "can't code" instead of "thinks at a higher level"?
- Is the vulnerability calibrated correctly - honest without being self-pitying?
- Would you share this on LinkedIn without cringing?

### 4. Audience & Impact

- Target reader: engineers using AI daily, YC founders, former colleagues. Does it land?
- Does the reader learn something or just watch someone think out loud?
- Would you read the whole thing or skim to the end?
- Is there a "so what" for the reader, or is it purely personal?
- Has this been written before? Search for similar articles. What's different here?

### 5. Sensitivity & Risk

- Any references to former employers that could cause problems?
- Are any references identifiable to specific people or companies?
- Any claims that could be challenged or fact-checked against public data?

### 6. Editorial Polish

- Read aloud (mentally). Where does it drag?
- Are any sentences doing the same work twice?
- Does the structure fit the word count?
- Does the opening hook hold for the first 3 paragraphs?
- Is the transition between sections smooth or jarring?
- Does the ending land?

## Output

For each review, provide:
1. **Verdict**: ready / needs minor fixes / needs rework
2. **Issues found** (numbered, specific, with line references)
3. **Suggested fixes** (exact replacement text where applicable)

Then a final summary: publish, revise, or hold. Be direct. The author wants honest assessment, not encouragement.

Save results to `~/Developer/seanfloyd.dev/.claude/tasks/pre-publish-review-results.md`.
