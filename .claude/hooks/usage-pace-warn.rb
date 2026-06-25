#!/usr/bin/env ruby
# frozen_string_literal: true

# Warn the agent once it crosses its WEEKLY DAILY ALLOWANCE -- both at the start
# of a turn AND mid-turn during long work. Wired to two hook events:
#   UserPromptSubmit -> fires each turn / autonomous-loop iteration (the decision
#                       point). Emits the warning as plain stdout, which Claude
#                       Code adds to context on exit 0.
#   PostToolUse      -> fires after every tool, so a single long turn grinding
#                       through many tools still gets warned. Emits
#                       hookSpecificOutput.additionalContext (shown next to the
#                       tool result). THROTTLED so it warns at most once per
#                       ~30 min (USAGE_PACE_THROTTLE_SECS), not after every tool.
#
# Allowance model: each day of the 7-day window grants ~14.29% (= 1/7) of the
# weekly pool. By day N you may spend up to N x 14.29% cumulatively. Today is
# counted in full (ceil), so the whole of "today" is available up front:
#   day       = ceil(days_elapsed_in_window), clamped 1..7
#   allowance = day / 7 * 100   (= day x 14.29%)
# Warn only when used% exceeds the allowance. Under it == banked breathing room,
# so stay quiet. Deliberately more lenient than the status line's hatch.
#
# Data source: ~/.claude/usage-cache.json, mirrored by the status line on every
# render. No CLI/API exposes the live subscription budget; this is only as fresh
# as the last render -- so mid-turn warnings work in interactive sessions (the
# bar re-renders on activity) but a pure background job with no TUI has a stale
# cache and we stay silent. Fails open and SILENT throughout: missing/stale/
# garbled cache or any error emits nothing, never a false alarm.
require "json"

CACHE         = File.expand_path(ENV["USAGE_CACHE"] || "~/.claude/usage-cache.json")
STALE_SECS    = (ENV["USAGE_PACE_STALE_SECS"]    || "3600").to_i # ignore data older than this
THROTTLE_SECS = (ENV["USAGE_PACE_THROTTLE_SECS"] || "1800").to_i # min gap between PostToolUse warnings
TMP           = ENV["TMPDIR"] || "/tmp"
WEEK          = 7 * 86_400
PER_DAY       = 100.0 / 7 # ~14.29% of the weekly pool granted per day

def bail = exit(0) # fail open + silent: no warning is better than a wrong one

def num(hash, key)
  v = hash.is_a?(Hash) ? hash[key] : nil
  v.is_a?(Numeric) ? v : nil
end

def fmt_dur(secs)
  secs = secs.to_i
  return "now" if secs <= 0

  d, r = secs.divmod(86_400)
  h = r / 3_600
  return "#{d}d#{h}h" if d.positive?

  "#{h}h"
end

# Read the hook payload to learn which event fired and the session (for the
# per-session throttle marker). Never raise on bad input.
payload = begin
  JSON.parse($stdin.read)
rescue StandardError
  {}
end
payload = {} unless payload.is_a?(Hash)
event   = payload["hook_event_name"].is_a?(String) ? payload["hook_event_name"] : "UserPromptSubmit"
session = payload["session_id"].is_a?(String) ? payload["session_id"].gsub(/[^\w.-]/, "") : "global"

bail unless File.exist?(CACHE)

data = begin
  JSON.parse(File.read(CACHE))
rescue StandardError
  bail
end

captured = num(data, "captured_at")
bail if captured.nil?

now = Time.now.to_i
bail if now - captured > STALE_SECS # too old to trust; don't risk a false warning

rl = data["rate_limits"]
bail unless rl.is_a?(Hash) # non-Hash here would crash Hash#dig -> stay quiet
weekly   = rl["seven_day"]
wk_used  = num(weekly, "used_percentage")
wk_reset = num(weekly, "resets_at")
bail if wk_used.nil? || wk_reset.nil?

# Plausibility guards: turn a silently-WRONG number into silently-safe. A used%
# outside 0..100, or a reset not within ~a week of now (e.g. a millisecond epoch
# from a writer change), is bad data -- bail rather than emit a bogus warning.
bail unless wk_used.between?(0, 100)
bail unless wk_reset.between?(now - 86_400, now + WEEK + 86_400)

# Days elapsed in the current window, counting today (ceil), clamped 1..7.
window_start = wk_reset - WEEK
day          = ((now - window_start).to_f / 86_400).ceil.clamp(1, 7)
allowance    = day * PER_DAY

bail if wk_used <= allowance # within the daily allowance -> breathing room, stay quiet

# Throttle: PostToolUse fires after every tool, so gate it to one warning per
# throttle window (~30 min). UserPromptSubmit is once per turn -- it always
# warns, but it refreshes the same stamp so an immediately-following PostToolUse
# stays quiet.
marker = File.join(TMP, "claude-usage-pace-#{session}")
last   = (File.read(marker).to_i rescue 0)

bail if event == "PostToolUse" && now - last < THROTTLE_SECS
File.write(marker, now.to_s) rescue nil

over = (wk_used - allowance).ceil # only reached when over allowance -> always >= 1
warning = format(
  "[usage-pace] WEEKLY budget over the daily allowance: %d%% used vs %d%% allowed " \
  "by day %d of 7 (~14.3%%/day; resets in %s) -- ~%dpts over. You have spent more " \
  "than your cumulative daily share -- prefer landing in-flight work over starting " \
  "new threads, and check " \
  "`ruby ~/.claude/skills/checking-usage/usage.rb` before any big push.",
  wk_used.round, allowance.round, day, fmt_dur(wk_reset - now), over
)

if event == "PostToolUse"
  # Structured form: shown next to the tool result mid-turn.
  puts JSON.generate(
    hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: warning }
  )
else
  # UserPromptSubmit (and any other): plain stdout is added to context on exit 0.
  puts warning
end
exit 0
