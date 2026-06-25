#!/usr/bin/env ruby
# frozen_string_literal: true

# Reports current time + remaining Claude usage budget (session and weekly),
# reading the cache the status line writes on every render
# (see ~/.claude/statusline-command.rb). There is no other on-demand source for
# this data on the machine -- the live rate_limits payload only reaches the
# status line process, so this reader is only as fresh as the last render.
#
# The point of this tool is a DECISION, not just numbers. The trap (learned the
# hard way) is treating a near-full SESSION window as "out of budget" and
# stopping -- the 5h window resets in hours; only the WEEKLY budget actually
# running low is a real "stop for the week" signal. The verdict makes that
# distinction explicit.
#
# Exit codes: 0 = report printed, 2 = no/garbled cache (can't advise).
require "json"

CACHE = File.expand_path(ENV["USAGE_CACHE"] || "~/.claude/usage-cache.json")

# Tunable thresholds (percent used).
SESSION_FULL = (ENV["USAGE_SESSION_FULL"] || "92").to_f   # 5h window effectively spent
WEEKLY_LOW   = (ENV["USAGE_WEEKLY_LOW"]   || "90").to_f   # weekly budget genuinely low
STALE_SECS   = (ENV["USAGE_STALE_SECS"]   || "900").to_i  # 15 min -> warn the number is old
WEEK         = 7 * 86_400

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

def num(hash, key)
  v = hash.is_a?(Hash) ? hash[key] : nil
  v.is_a?(Numeric) ? v : nil
end

unless File.exist?(CACHE)
  warn <<~MSG
    No usage cache at #{CACHE}.

    The status line writes it on every render, so this is empty only if the
    status line hasn't drawn yet this session (e.g. a pure background job with no
    TUI attached). Open/refresh an interactive Claude Code window on this machine
    to populate it, then re-run. Don't guess the numbers.
  MSG
  exit 2
end

data = begin
  JSON.parse(File.read(CACHE))
rescue StandardError => e
  warn "Usage cache is unreadable (#{e.class}: #{e.message}). Treat budget as unknown; don't guess."
  exit 2
end

now        = Time.now
captured   = data["captured_at"].is_a?(Numeric) ? data["captured_at"] : nil
age        = captured ? (now.to_i - captured) : nil
rl         = data["rate_limits"].is_a?(Hash) ? data["rate_limits"] : {}
session    = rl["five_hour"]
weekly     = rl["seven_day"]

ses_used   = num(session, "used_percentage")
ses_reset  = num(session, "resets_at")
wk_used    = num(weekly, "used_percentage")
wk_reset   = num(weekly, "resets_at")

lines = []
lines << format("time     %s", now.strftime("%Y-%m-%d %H:%M %Z (%a)"))

freshness =
  if age.nil?           then "unknown age"
  elsif age <= 90       then "fresh (#{age}s ago)"
  elsif age <= STALE_SECS then "#{fmt_dur(age)} old"
  else "STALE -- #{fmt_dur(age)} old; status line not rendering. The real budget may have moved."
  end
lines << "data     #{freshness}"
lines << ""

if ses_used
  seg = format("SESSION  %d%% used", ses_used.round)
  seg += "  ·  resets in #{fmt_dur(ses_reset - now.to_i)}" if ses_reset
  seg += "  (5h window)"
  lines << seg
else
  lines << "SESSION  (no five_hour data in payload)"
end

if wk_used
  seg = format("WEEKLY   %d%% used", wk_used.round)
  seg += "  ·  resets in #{fmt_dur(wk_reset - now.to_i)}" if wk_reset
  seg += "  (7d window)"
  lines << seg

  if wk_reset
    elapsed   = ((now.to_i - (wk_reset - WEEK)).to_f / WEEK).clamp(0.0, 1.0) * 100
    delta     = wk_used - elapsed                    # +ve = burning faster than even
    days_left = [(wk_reset - now.to_i).to_f / 86_400, 0.0001].max
    remaining = 100 - wk_used
    today_cap = [remaining, remaining / days_left].min.clamp(0, 100)  # spend-and-still-last
    pace_note =
      if delta.abs < 2 then "on pace"
      elsif delta.positive? then format("%dpts AHEAD of pace (burning fast)", delta.round)
      else format("%dpts UNDER pace (room to spend faster)", (-delta).round)
      end
    lines << format("         %d%% of week elapsed -> %s", elapsed.round, pace_note)
    lines << format("         budget: ~%d%% of the weekly pool is safe to spend today", today_cap.round)
  end
else
  lines << "WEEKLY   (no seven_day data in payload)"
end

lines << ""

verdict =
  if ses_used && ses_used >= SESSION_FULL && (wk_used.nil? || wk_used < WEEKLY_LOW)
    left = wk_used ? "#{(100 - wk_used).round}%" : "budget"
    rst  = ses_reset ? " (resets in #{fmt_dur(ses_reset - now.to_i)})" : ""
    "SESSION-LIMITED -- 5h window almost full#{rst}. TEMPORARY: pause and resume " \
      "after the session resets. Do NOT call the work done while #{left} of the weekly pool remains."
  elsif wk_used && wk_used >= WEEKLY_LOW
    "WIND DOWN -- weekly pool is nearly spent (#{(100 - wk_used).round}% left). " \
      "Land what's in flight and stop for the week."
  elsif wk_used.nil? && ses_used.nil?
    "UNKNOWN -- payload had no budget data. Don't guess; re-render the status line."
  else
    head = wk_used ? "#{(100 - wk_used).round}% weekly headroom" : "weekly budget healthy"
    "KEEP GOING -- #{head}; session has room. Spend the budget you were asked to spend."
  end
lines << "VERDICT  #{verdict}"

puts lines.join("\n")
