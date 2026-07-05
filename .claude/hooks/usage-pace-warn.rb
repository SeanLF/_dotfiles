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
# Data source: the per-session snapshots the status line writes every render
# (usage-cache-<session_id>.json). rate_limits is ACCOUNT-GLOBAL but each snapshot is
# frozen at a session's last API turn, so with N concurrent sessions a single shared
# file is last-writer-wins across N staleness levels -- we reconcile across the
# per-session files instead (current window + max used%, mirroring the checking-usage
# reader; keep the two in sync). context_window is SESSION-LOCAL, so the compaction
# check reads THIS session's OWN snapshot file directly (matched by session_id) --
# reliable for every session now, not just whichever one last wrote a shared cache.
#
# No CLI/API exposes the live budget, so this is only as fresh as the last render:
# mid-turn warnings work in interactive sessions (the bar re-renders on activity);
# a pure background job with no TUI has stale snapshots and we stay silent. Fails
# open and SILENT throughout: missing/stale/garbled cache or any error emits
# nothing, never a false alarm.
require "json"

CACHE         = File.expand_path(ENV["USAGE_CACHE"] || "~/.claude/usage-cache.json")
CACHE_GLOB    = CACHE.sub(/\.json\z/, "-*.json")  # per-session snapshots
STALE_SECS    = (ENV["USAGE_PACE_STALE_SECS"]    || "3600").to_i # ignore data older than this
THROTTLE_SECS = (ENV["USAGE_PACE_THROTTLE_SECS"] || "1800").to_i # min gap between weekly warnings
CTX_WARN      = (ENV["USAGE_CTX_WARN"]           || "85").to_f   # context % that trips a compaction warning
CTX_THROTTLE  = (ENV["USAGE_CTX_THROTTLE_SECS"]  || "600").to_i  # min gap between compaction warnings (more urgent)
COAST_SECS    = (ENV["USAGE_PACE_COAST_SECS"]    || "43200").to_i # reset this close (12h) -> unspent is use-it-or-lose-it, so don't pace-nag
SES_WARN      = (ENV["USAGE_SES_WARN"]           || "85").to_f   # 5h session % that trips an auto-throttle heads-up
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
  h, r = r.divmod(3_600)
  m, = r.divmod(60)
  return "#{d}d#{h}h" if d.positive?
  return "#{h}h#{m}m" if h.positive?

  "#{m}m"
end

def fmt_size(n)
  return nil unless n.is_a?(Numeric) && n.positive?

  n >= 1_000_000 ? "#{(n / 1_000_000.0).round}M" : "#{(n / 1000.0).round}k"
end

# All per-session snapshots (legacy single file as fallback before any re-render).
# Garbled files skipped. => Array<Hash>. Mirrors checking-usage/usage.rb#load_snapshots.
def load_snapshots
  files = Dir.glob(CACHE_GLOB)
  files = [CACHE] if files.empty? && File.exist?(CACHE)
  files.filter_map do |f|
    d = begin JSON.parse(File.read(f)) rescue nil end
    d if d.is_a?(Hash)
  end
end

# Reconcile one ACCOUNT-GLOBAL window across snapshots frozen at differing staleness:
# trust only a still-ahead (plausible) reset -- dropping an idle session's expired 5h
# window -- and take the MAX used% on the current window (monotonic -> freshest wins).
# => [used, reset] or [nil, nil]. Mirrors checking-usage/usage.rb#reconcile_window.
def reconcile_window(snaps, key, now, max_ahead)
  live = snaps.filter_map do |d|
    rl = d["rate_limits"]
    w  = rl.is_a?(Hash) ? rl[key] : nil
    next unless w.is_a?(Hash) && w["used_percentage"].is_a?(Numeric)
    r = w["resets_at"]
    next unless r.is_a?(Numeric) && r > now && r <= now + max_ahead
    { used: w["used_percentage"], reset: r }
  end
  return [nil, nil] if live.empty?

  reset = live.map { |e| e[:reset] }.max
  best  = live.select { |e| e[:reset] == reset }.max_by { |e| e[:used] }
  [best[:used], best[:reset]]
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

snaps = load_snapshots
bail if snaps.empty?

now = Time.now.to_i
# Account-global freshness = the most recent render across ALL sessions (captured_at
# is render time, not data age). If nothing has rendered recently, the reconciled
# budget is too old to warn on -- stay silent rather than risk a stale false warning.
account_captured = snaps.filter_map { |d| num(d, "captured_at") }.max
account_fresh    = account_captured && (now - account_captured <= STALE_SECS)

# Each warning is an independent signal (its own throttle marker) so a fine weekly
# budget never suppresses a compaction warning, or vice versa.
Warn = Struct.new(:key, :throttle, :text)
warnings = []

# --- WEEKLY budget vs cumulative daily allowance (account-global -> reconciled across
# sessions; reconcile_window guarantees a plausible still-ahead reset) ---
wk_used, wk_reset = account_fresh ? reconcile_window(snaps, "seven_day", now, WEEK + 86_400) : [nil, nil]
if wk_used && wk_reset && wk_used.between?(0, 100)
  to_reset  = wk_reset - now
  day       = ((now - (wk_reset - WEEK)).to_f / 86_400).ceil.clamp(1, 7)
  allowance = day * PER_DAY
  # Near a reset, unspent weekly budget is use-it-or-lose-it, so being "over" the
  # cumulative daily share is not a problem -- suppress the pace nag entirely
  # rather than push a cautious model to wind down when it should burn down.
  if wk_used > allowance && to_reset > COAST_SECS
    over = (wk_used - allowance).ceil
    warnings << Warn.new("pace", THROTTLE_SECS, format(
      "[usage-pace] WEEKLY pace: %d%% used vs ~%d%% (your day-%d/7 share, ~14.3%%/day; " \
      "resets in %s) -- ~%dpts ahead. This is a PACE signal, NOT a stop order. Weigh the cost: " \
      "if finishing the current task is cheaper than a clean handover, push through -- a cold " \
      "restart pays to rebuild context. If you do stop, checkpoint properly: update the relevant " \
      "docs and leave a handover note so the next session resumes cheaply; don't just drop it " \
      "mid-task. Running unattended, aim for a comfortable checkpoint as you near the limit, not " \
      "the moment you cross the share. Run `ruby ~/.claude/skills/checking-usage/usage.rb` " \
      "before a big new push.",
      wk_used.round, allowance.round, day, fmt_dur(to_reset), over
    ))
  end
end

# --- 5h SESSION window nearing full (account-global -> always OK to read). A long
# or looping session that saturates this auto-throttles; a heads-up lets it land
# work before the pause instead of getting cut mid-task. Not "done for the week" --
# the 5h window resets in hours, so it is a short wait if the weekly pool has room. ---
ses_used, ses_reset = account_fresh ? reconcile_window(snaps, "five_hour", now, 6 * 3_600) : [nil, nil]
if ses_used && ses_reset && ses_used.between?(0, 100) && ses_used >= SES_WARN
  warnings << Warn.new("session", THROTTLE_SECS, format(
    "[usage-session] 5h SESSION window at %d%% (resets in %s) -- you will auto-throttle soon. " \
    "Land or checkpoint in-flight work before the pause. This is a short wait, not done for " \
    "the week, if the weekly pool still has room.",
    ses_used.round, fmt_dur(ses_reset - now)
  ))
end

# --- CONTEXT nearing auto-compaction (session-local -> read THIS session's OWN
# snapshot directly, matched by session_id, with its own freshness gate) ---
own     = session_id ? snaps.find { |d| d["session_id"] == session_id } : nil
own_cap = num(own, "captured_at")             # num self-guards a nil own
cw      = own && own["context_window"]        # load_snapshots yields only Hashes
if own_cap && now - own_cap <= STALE_SECS && cw.is_a?(Hash)
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
