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
require_relative "burn"

CACHE      = File.expand_path(ENV["USAGE_CACHE"] || "~/.claude/usage-cache.json")
CACHE_GLOB = CACHE.sub(/\.json\z/, "-*.json")  # per-session snapshots the status line writes
HISTORY    = File.expand_path(ENV["USAGE_HISTORY"] || "~/.claude/rate-limit-history.jsonl")

# Tunable thresholds (percent used).
SESSION_FULL = (ENV["USAGE_SESSION_FULL"] || "92").to_f   # 5h window effectively spent
SES_SOON_SECS = (ENV["USAGE_SES_SOON_SECS"] || "900").to_i # projected 5h cap this close -> SESSION-LIMITED early
WEEKLY_LOW   = (ENV["USAGE_WEEKLY_LOW"]   || "90").to_f   # weekly budget genuinely low
STALE_SECS   = (ENV["USAGE_STALE_SECS"]   || "900").to_i  # 15 min -> warn the number is old
# Reset-proximity: burning fast is only a problem if it strands you IDLE for a
# meaningful stretch before the window resets. Unspent budget near a reset is
# use-it-or-lose-it, so we don't nag a deliberate burn-down.
IDLE_WARN_SECS  = (ENV["USAGE_IDLE_WARN_H"]     || "24").to_f * 3600  # idle-before-reset that earns a PACE DOWN
COAST_SECS      = (ENV["USAGE_COAST_H"]         || "12").to_f * 3600  # reset this close -> COAST, don't WIND DOWN
BURNDOWN_FORFEIT = (ENV["USAGE_BURNDOWN_FORFEIT"] || "15").to_f       # unspent-at-reset (at ~1/7/day pace) worth a BURN DOWN nudge
WEEK            = 7 * 86_400

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

# Every session's snapshot (usage-cache-<session_id>.json). Falls back to the legacy
# single file if no per-session files exist yet (right after an upgrade). Garbled
# files are skipped, not fatal. => [files_that_existed, Array<Hash>] -- the file list
# lets the caller tell "nothing has rendered" (no files) apart from "all snapshots are
# corrupt" (files present, none parsed), which warrant different advice.
def load_snapshots
  files = Dir.glob(CACHE_GLOB)
  files = [CACHE] if files.empty? && File.exist?(CACHE)
  snaps = files.filter_map do |f|
    d = begin JSON.parse(File.read(f)) rescue nil end
    d if d.is_a?(Hash) && d["rate_limits"].is_a?(Hash)
  end
  [files, snaps]
end

# Reconcile one ACCOUNT-GLOBAL window (five_hour / seven_day) across snapshots that
# are each frozen at a different session's last API turn. Both windows are global, so
# the disagreement between sessions is pure staleness. Two rules recover the truth:
#   1. Only trust a snapshot whose reset is still AHEAD (and plausibly so, <= max_ahead).
#      This drops an idle session's already-EXPIRED 5h window -- the "resets: now" bug.
#   2. Among snapshots on the current window (the latest reset), take the MAX used%:
#      usage is monotonic within a window, so the highest reading is the freshest.
# No live snapshot -> [nil, nil]; the caller reports the window as unknown, never a
# stale/expired one. Needs no notion of "which session am I", so it behaves the same
# invoked inside a session or from a bare shell / background job.
def reconcile_window(snaps, key, now, max_ahead)
  live = snaps.filter_map do |d|
    w = d["rate_limits"][key]
    next unless w.is_a?(Hash) && w["used_percentage"].is_a?(Numeric)
    r = w["resets_at"]
    next unless r.is_a?(Numeric) && r > now && r <= now + max_ahead
    { used: w["used_percentage"], reset: r }
  end
  return [nil, nil] if live.empty?

  reset = live.map { |e| e[:reset] }.max        # latest reset = the current window
  best  = live.select { |e| e[:reset] == reset }.max_by { |e| e[:used] }
  [best[:used], best[:reset]]
end

now          = Time.now
files, snaps = load_snapshots
if snaps.empty?
  warn(files.empty? ? <<~ABSENT : <<~CORRUPT)
    No usage snapshots matching #{CACHE_GLOB}.

    The status line writes one per session on every render, so this is empty only if
    no interactive Claude Code window has drawn on this machine recently (e.g. a pure
    background job with no TUI attached). Open/refresh an interactive window to
    populate it, then re-run. Don't guess the numbers.
  ABSENT
    Usage snapshots exist (#{files.size}) but none is readable -- corrupt or
    partially written. Treat budget as unknown; don't guess. A fresh status-line
    render will rewrite them; re-run once an interactive window has redrawn.
  CORRUPT
  exit 2
end

# Freshness = the most recent render across ALL live sessions. captured_at is render
# time, not data age (an idle session re-renders a frozen payload), so this detects
# "nothing is rendering at all" -- the real staleness signal -- rather than per-value age.
captured   = snaps.filter_map { |d| d["captured_at"] if d["captured_at"].is_a?(Numeric) }.max
age        = captured ? (now.to_i - captured) : nil

# reconcile_window already restricts to a plausible, still-ahead reset, so no separate
# resets_at plausibility guard is needed -- an implausible/expired reset simply never wins.
ses_used, ses_reset = reconcile_window(snaps, "five_hour", now.to_i, 6 * 3_600)
wk_used,  wk_reset  = reconcile_window(snaps, "seven_day", now.to_i, WEEK + 86_400)

# Read the burn history once (raw; may be nil if unreadable), then reconcile it into
# ONE account-global series PER window -- the log interleaves every session's samples,
# so each field is collapsed to its current-window running max independently. weekly
# uses the whole-run slope; the 5h session a short-horizon least-squares fit.
history    = Burn.read(HISTORY, now.to_i)
wk_hist    = Burn.envelope(history, "wk", "wk_reset")
ses_hist   = Burn.envelope(history, "ses", "ses_reset")
ses_soon   = false  # projected 5h cap is imminent (fast burst), even if not yet >= SESSION_FULL

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

  # Short-horizon burn on the 5h window: honest over minutes (no idle gaps in an
  # active burst), and hitting the cap is a real, imminent throttle -- so this rate
  # earns its keep where the weekly 24/7 projection doesn't.
  sp = Burn.project_recent(ses_hist, now.to_i, field: "ses")
  if sp
    cap_in = sp[:hours_to_cap] * 3600
    rate   = sp[:rate_per_h] >= 60 ? format("%.1f%%/min", sp[:rate_per_h] / 60.0) : format("%.1f%%/h", sp[:rate_per_h])
    if ses_reset && (ses_reset - now.to_i) <= cap_in
      lines << format("         burn: ~%s -> window resets (in %s) before you'd cap, fine", rate, fmt_dur(ses_reset - now.to_i))
    else
      lines << format("         burn: ~%s -> 5h cap in ~%s at this rate; land work before the pause", rate, fmt_dur(cap_in))
      ses_soon = cap_in <= SES_SOON_SECS
    end
  end
else
  # Snapshots exist but none is on a live 5h window: every session's 5h reading has
  # already expired (all idle past their last window). 5h is account-global, so this
  # is genuinely unknown until a session hits the API in the current window -- not a
  # missing field. Reported honestly rather than echoing a stale/expired window.
  lines << "SESSION  (no live 5h window across sessions -- all snapshots predate the last reset)"
end

# Past the cumulative day-N/7 share (front-loaded) AND not near reset -- the honest
# pace signal, matching usage-pace-warn.rb so the skill and hook never disagree.
pace_warn = false
# Would the measured rate hit the cap before reset IF sustained non-stop? Kept as an
# informational aside for the (rare) unattended-loop case -- it no longer drives the
# verdict, because sustained 24/7 burn effectively never happens interactively.
burn_warn = false

if wk_used
  seg = format("WEEKLY   %d%% used", wk_used.round)
  seg += "  ·  resets in #{fmt_dur(wk_reset - now.to_i)}" if wk_reset
  seg += "  (7d window)"
  lines << seg

  if wk_reset
    elapsed   = ((now.to_i - (wk_reset - WEEK)).to_f / WEEK).clamp(0.0, 1.0) * 100
    delta     = wk_used - elapsed                    # +ve = burning faster than even
    days_left = [(wk_reset - now.to_i).to_f / 86_400, 0.0001].max
    # Cumulative 1/7-per-day share (today counted in full, ceil), matching the hook.
    # Being over it == front-loaded, not doomed; near a reset it's use-it-or-lose-it.
    day       = ((now.to_i - (wk_reset - WEEK)).to_f / 86_400).ceil.clamp(1, 7)
    allowance = day * (100.0 / 7)
    pace_warn = wk_used > allowance && (wk_reset - now.to_i) > COAST_SECS
    remaining = [100 - wk_used, 0.0].max
    today_cap = [remaining, remaining / days_left].min.clamp(0, 100)  # even-burn daily share
    pace_note =
      if delta.abs < 2 then "on even-burn pace"
      elsif delta.positive? then format("%dpts AHEAD of even-burn pace (burning fast)", delta.round)
      else format("%dpts UNDER even-burn pace -- expected unless you run 24/7 (idle/sleep counts as elapsed)", (-delta).round)
      end
    lines << format("         %d%% of week elapsed -> %s", elapsed.round, pace_note)
    # today_cap is an even-burn PACE guide, not a real quota: there is no daily
    # cap, and it can't see how much of today you've already spent. Spending over
    # it just shrinks tomorrow's share -- it self-corrects, it doesn't lock you out.
    lines << format("         pace guide: ~%d%%/day spends the rest evenly to reset (not a hard cap)", today_cap.round)

    # Measured burn from the reconciled weekly envelope (reset-robust): if the current
    # run's rate would reach 100% before the window resets, that's the real throttle
    # warning -- the weekly ceiling nobody advertises, arriving early. `history` is nil
    # only when a non-empty log won't parse (drift/corruption) -- surface that rather
    # than let a dead projection read as "all clear".
    proj    = Burn.project(wk_hist)
    if proj
      secs_to_cap   = proj[:hours_to_cap] * 3600
      time_to_reset = wk_reset - now.to_i
      idle          = time_to_reset - secs_to_cap  # how long you'd be throttled before the reset
      if secs_to_cap >= time_to_reset
        lines << format("         burn: ~%.1f%%/h -> even non-stop, resets before you'd reach the cap, fine", proj[:burn_per_h])
      else
        burn_warn = idle > IDLE_WARN_SECS
        tail = burn_warn ? "~#{fmt_dur(idle)} idle before reset -- ease off IF you'll sustain this unattended" : "just shy of reset -> burn it down freely"
        lines << format("         burn: ~%.1f%%/h; IF sustained 24/7, cap in ~%s -- %s (idle/sleep stretches this out)", proj[:burn_per_h], fmt_dur(secs_to_cap), tail)
      end
    elsif history.nil?
      lines << "         burn: history unreadable -- projection unavailable (not a clear signal)"
    end
  end
else
  lines << "WEEKLY   (no live 7d window across sessions -- snapshots missing or stale)"
end

lines << ""

# Weekly headroom, floored at 0 so an over-budget window (used_percentage > 100)
# never prints a nonsensical negative "% left".
wk_left = wk_used ? [100 - wk_used, 0].max.round : nil

# Near-reset burn-down: at your ~1/7-per-day pace, how much would still be unspent
# when the window resets? That headroom resets to ZERO (can't bank), so a large
# projected forfeit means the honest advice is "spend it," not coast. Self-gating:
# fires only when there's genuine surplus, so never when you're actually constrained.
forfeit   = nil
burn_down = false
if wk_used && wk_reset && wk_used < WEEKLY_LOW && wk_left
  days_to_reset = [(wk_reset - now.to_i).to_f / 86_400, 0].max
  forfeit       = (wk_left - days_to_reset * (100.0 / 7)).round
  burn_down     = forfeit >= BURNDOWN_FORFEIT
end

verdict =
  if ses_used && (ses_used >= SESSION_FULL || ses_soon) && (wk_used.nil? || wk_used < WEEKLY_LOW)
    left  = wk_left ? "#{wk_left}%" : "budget"
    rst   = ses_reset ? " (resets in #{fmt_dur(ses_reset - now.to_i)})" : ""
    state = ses_used >= SESSION_FULL ? "5h window almost full" : "on pace to hit the 5h cap soon at your current burn"
    "SESSION-LIMITED -- #{state}#{rst}. TEMPORARY: land in-flight work, then pause and resume " \
      "after the session resets. Do NOT call the work done while #{left} of the weekly pool remains."
  elsif wk_used && wk_used >= WEEKLY_LOW && wk_reset && (wk_reset - now.to_i) <= COAST_SECS
    "COAST -- weekly is nearly spent (#{wk_left}% left) but it resets in " \
      "#{fmt_dur(wk_reset - now.to_i)}. Unspent budget is use-it-or-lose-it, so spend the rest freely."
  elsif wk_used && wk_used >= WEEKLY_LOW
    "WIND DOWN -- weekly pool is nearly spent (#{wk_left}% left). Land what's in flight and " \
      "stop for the week. Finish the task if that's cheaper than a handover; otherwise stop at a " \
      "natural boundary and checkpoint properly -- update docs and leave a handover note so the " \
      "next session resumes cheaply, don't abandon it mid-way."
  elsif burn_down
    "BURN DOWN -- #{wk_left}% unspent, reset in #{fmt_dur(wk_reset - now.to_i)}; at your " \
      "~1/7/day pace ~#{forfeit}% would go UNSPENT and reset to zero (you can't bank it). If you " \
      "have valuable but deferrable work -- deep passes, parallel fan-outs, research, an overnight " \
      "loop -- spend it now: go bigger/parallel. Not busywork, but don't waste the headroom."
  elsif wk_used.nil? && ses_used.nil?
    "UNKNOWN -- payload had no budget data. Don't guess; re-render the status line."
  elsif pace_warn
    head = wk_left ? "#{wk_left}% weekly headroom" : "weekly headroom"
    "PACE DOWN -- #{head}, but you're past your ~1/7-per-day share this week. Front-loaded, " \
      "not doomed -- it self-corrects for interactive work. Before a big new thread, spread the " \
      "spend; finish or checkpoint what's in flight first. (Recent burn IF sustained 24/7 would " \
      "throttle you pre-reset -- but you rarely run unattended, so treat that as a caveat.)"
  else
    head = wk_left ? "#{wk_left}% weekly headroom" : "weekly budget healthy"
    "KEEP GOING -- #{head}; session has room. Spend the budget you were asked to spend."
  end
lines << "VERDICT  #{verdict}"

puts lines.join("\n")
