#!/usr/bin/env ruby
# frozen_string_literal: true

# Situational-awareness hook: warns the agent about two things it otherwise can't
# see mid-turn, so long/autonomous work doesn't blow past a limit unaware.
#
#   1. WEEKLY budget over the daily allowance (the ceiling nobody advertises).
#   2. CONTEXT window nearing auto-compaction (so it can checkpoint / /compact at
#      a clean point instead of getting cut mid-task).
#
# Wired to two events:
#   UserPromptSubmit -> fires each turn / loop iteration (the decision point).
#                       Emits plain stdout, which Claude Code adds to context.
#   PostToolUse      -> fires after every tool, so a single long turn still gets
#                       warned. Emits hookSpecificOutput.additionalContext, and is
#                       THROTTLED (per signal) so it doesn't warn after every tool.
#
# Weekly allowance model: each day of the 7-day window grants ~14.29% (= 1/7) of
# the pool. By day N you may spend up to N x 14.29% cumulatively. Today counts in
# full (ceil), so all of "today" is available up front:
#   day = ceil(days_elapsed_in_window) clamped 1..7 ; allowance = day/7 * 100
# Warn only when used% exceeds that. Under it == banked breathing room, stay quiet.
#
# Data source: ~/.claude/usage-cache.json, mirrored by the status line every
# render. rate_limits is account-global (trustworthy from any session), but
# context_window is SESSION-LOCAL -- so the compaction check fires only when the
# cache was last written by THIS session (session_id match); otherwise we can't
# tell if the cached context is ours and we stay silent.
#
# No CLI/API exposes the live budget, so this is only as fresh as the last render:
# mid-turn warnings work in interactive sessions (the bar re-renders on activity);
# a pure background job with no TUI has a stale cache and we stay silent. Fails
# open and SILENT throughout: missing/stale/garbled cache or any error emits
# nothing, never a false alarm.
require "json"

CACHE         = File.expand_path(ENV["USAGE_CACHE"] || "~/.claude/usage-cache.json")
STALE_SECS    = (ENV["USAGE_PACE_STALE_SECS"]    || "3600").to_i # ignore data older than this
THROTTLE_SECS = (ENV["USAGE_PACE_THROTTLE_SECS"] || "1800").to_i # min gap between weekly warnings
CTX_WARN      = (ENV["USAGE_CTX_WARN"]           || "85").to_f   # context % that trips a compaction warning
CTX_THROTTLE  = (ENV["USAGE_CTX_THROTTLE_SECS"]  || "600").to_i  # min gap between compaction warnings (more urgent)
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

def fmt_size(n)
  return nil unless n.is_a?(Numeric) && n.positive?

  n >= 1_000_000 ? "#{(n / 1_000_000.0).round}M" : "#{(n / 1000.0).round}k"
end

# Read the hook payload to learn which event fired and the session (raw, for the
# session-local context match; sanitized, for the throttle marker filename).
payload = begin
  JSON.parse($stdin.read)
rescue StandardError
  {}
end
payload    = {} unless payload.is_a?(Hash)
event      = payload["hook_event_name"].is_a?(String) ? payload["hook_event_name"] : "UserPromptSubmit"
session_id = payload["session_id"].is_a?(String) ? payload["session_id"] : nil
marker_key = (session_id || "global").gsub(/[^\w.-]/, "")

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

# Each warning is an independent signal (its own throttle marker) so a fine weekly
# budget never suppresses a compaction warning, or vice versa.
Warn = Struct.new(:key, :throttle, :text)
warnings = []

# --- WEEKLY budget vs cumulative daily allowance (account-global -> always OK to read) ---
rl     = data["rate_limits"]
weekly = rl.is_a?(Hash) ? rl["seven_day"] : nil
wk_used  = num(weekly, "used_percentage")
wk_reset = num(weekly, "resets_at")
# Plausibility guards: a used% outside 0..100 or a reset not within ~a week (e.g. a
# millisecond epoch from a writer change) is bad data -- skip rather than misfire.
if wk_used && wk_reset && wk_used.between?(0, 100) &&
   wk_reset.between?(now - 86_400, now + WEEK + 86_400)
  day       = ((now - (wk_reset - WEEK)).to_f / 86_400).ceil.clamp(1, 7)
  allowance = day * PER_DAY
  if wk_used > allowance
    over = (wk_used - allowance).ceil
    warnings << Warn.new("pace", THROTTLE_SECS, format(
      "[usage-pace] WEEKLY budget over the daily allowance: %d%% used vs %d%% allowed " \
      "by day %d of 7 (~14.3%%/day; resets in %s) -- ~%dpts over. You have spent more " \
      "than your cumulative daily share -- prefer landing in-flight work over starting " \
      "new threads, and check " \
      "`ruby ~/.claude/skills/checking-usage/usage.rb` before any big push.",
      wk_used.round, allowance.round, day, fmt_dur(wk_reset - now), over
    ))
  end
end

# --- CONTEXT nearing auto-compaction (session-local -> only if THIS session wrote the cache) ---
cw = data["context_window"]
if session_id && data["session_id"] == session_id && cw.is_a?(Hash)
  ctx  = num(cw, "used_percentage")
  size = fmt_size(num(cw, "context_window_size"))
  if ctx && ctx.between?(0, 100) && ctx >= CTX_WARN
    where = size ? " of the #{size} context window" : ""
    warnings << Warn.new("ctx", CTX_THROTTLE, format(
      "[context] this session is at %d%%%s -- auto-compaction is near. Land or checkpoint " \
      "important state now, and consider /compact at a clean point so it doesn't cut mid-task.",
      ctx.round, where
    ))
  end
end

bail if warnings.empty?

# Throttle per signal, and only on PostToolUse (which fires after every tool);
# UserPromptSubmit is once per turn and always emits. Refresh the marker only for
# signals we actually emit, so a suppressed one re-arms on its own schedule.
marker = ->(w) { File.join(TMP, "claude-#{w.key}-#{marker_key}") }
emit = warnings.reject do |w|
  event == "PostToolUse" && now - (File.read(marker[w]).to_i rescue 0) < w.throttle
end
emit.each { |w| File.write(marker[w], now.to_s) rescue nil }
bail if emit.empty?

text = emit.map(&:text).join("\n")
if event == "PostToolUse"
  puts JSON.generate(hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: text })
else
  puts text # UserPromptSubmit (and any other): plain stdout added to context on exit 0
end
exit 0
