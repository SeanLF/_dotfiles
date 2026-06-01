#!/usr/bin/env ruby
# frozen_string_literal: true

# Claude Code status line -- usage gauge (session + weekly budget), text only.
#
# Colour is unreliable in the status line (Claude Code dims/overrides ANSI), so
# this is deliberately monochrome: information is carried by shape and texture.
#   solid block  = budget used and on pace
#   hatch block  = budget used but PAST the on-pace line (burning too fast)
#   light shade  = remaining
# When you're within pace the bar is clean solid; an over-pace tail turns rough.
# The weekly bar widens with the terminal (COLUMNS) for finer resolution.
#
# It fails quiet (degrades to blank) so it never dumps a stack trace into the
# bar -- but anomalies are recorded in LOG, so a Claude Code payload change can't
# silently break the gauge with no trace. Watch it with:
#   tail -f ~/.claude/statusline.log
require "json"

EIGHTHS = [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"].freeze
SOLID   = "█"  # used, on pace
HATCH   = "▓"  # used, past the on-pace line
TRACK   = "░"  # remaining
WEEK    = 7 * 86_400  # seconds in the seven_day window
LOG     = File.expand_path(ENV["STATUSLINE_LOG"] || "~/.claude/statusline.log")

# Best-effort anomaly log: never raises, capped to the last 200 lines. The happy
# path writes nothing -- only malformed input or unexpected errors land here.
def log(level, msg)
  msg = msg.to_s.gsub(/\s*\n\s*/, " ").slice(0, 500)  # one entry is always one line
  prev = File.exist?(LOG) ? File.readlines(LOG) : []
  prev << "#{Time.now.strftime('%F %T')} [#{level}] #{msg}\n"
  File.write(LOG, prev.last(200).join)
rescue StandardError
  nil
end

# True if hash[key] is the expected type. Present-but-wrong-type logs a warning
# (signals a Claude Code schema change); a missing key is silent and expected.
def typed?(hash, key, type, label)
  value = hash[key]
  return true if value.is_a?(type)

  log("warn", "#{label} is #{value.class}, expected #{type}") unless value.nil?
  false
end

def fmt_dur(secs)
  secs = 0 if secs.negative?
  d, r = secs.divmod(86_400)
  h, r = r.divmod(3_600)
  m, = r.divmod(60)
  return "#{d}d#{h}h" if d.positive?
  return "#{h}h#{m}m" if h.positive?

  "#{m}m"
end

# Monochrome meter. fill = fraction used; cells beyond pace_frac render hatched.
def meter(used_frac, pace_frac, width)
  used_w = used_frac * width
  pace_w = (pace_frac || 1.0) * width
  (0...width).map do |i|
    over = (i + 0.5) >= pace_w
    if i + 1 <= used_w            # fully used cell
      over ? HATCH : SOLID
    elsif i < used_w              # leading edge (partial)
      frac = used_w - i
      over ? (frac >= 0.5 ? HATCH : TRACK) : EIGHTHS[[(frac * 8).round, 1].max]
    else                          # remaining
      TRACK
    end
  end.join
end

parts = []
begin
  data = begin
    JSON.parse($stdin.read)
  rescue JSON::ParserError => e
    log("warn", "stdin is not valid JSON: #{e.message}")
    {}
  end
  unless data.is_a?(Hash)
    log("warn", "top-level payload is #{data.class}, expected object") unless data.nil?
    data = {}
  end

  rl = data["rate_limits"]
  log("warn", "rate_limits is #{rl.class}, expected object") if rl && !rl.is_a?(Hash)
  rl = {} unless rl.is_a?(Hash)

  now  = Time.now.to_i
  cols = (ENV["COLUMNS"] || "120").to_i

  fh = rl["five_hour"]
  if typed?(rl, "five_hour", Hash, "five_hour") && typed?(fh, "used_percentage", Numeric, "five_hour.used_percentage")
    seg = "ses #{fh['used_percentage'].round}%"
    seg += " #{fmt_dur(fh['resets_at'] - now)}" if typed?(fh, "resets_at", Numeric, "five_hour.resets_at")
    parts << seg
  end

  sd = rl["seven_day"]
  if typed?(rl, "seven_day", Hash, "seven_day") && typed?(sd, "used_percentage", Numeric, "seven_day.used_percentage")
    used  = sd["used_percentage"]
    width = [[cols - 34, 40].min, 16].max
    if typed?(sd, "resets_at", Numeric, "seven_day.resets_at")
      reset     = sd["resets_at"]
      pace      = ((now - (reset - WEEK)).to_f / WEEK).clamp(0.0, 1.0)
      days_left = [(reset - now).to_f / 86_400, 0.0001].max
      day       = [100 - used, (100 - used) / days_left].min.clamp(0, 100)
      parts << "wk #{meter(used / 100.0, pace, width)} #{used.round}%"
      parts << "day #{day.round}%"
    else
      parts << "wk #{meter(used / 100.0, nil, width)} #{used.round}%"
    end
  end

  # rate_limits present but neither window key is there (e.g. a rename) -- would
  # otherwise blank the bar with no trace, the exact silent failure we're after.
  if !rl.empty? && !rl.key?("five_hour") && !rl.key?("seven_day")
    log("warn", "rate_limits has neither five_hour nor seven_day (keys: #{rl.keys.join(', ')})")
  end
rescue StandardError => e
  log("error", "#{e.class}: #{e.message} @ #{e.backtrace&.first}")
end

print parts.join("  ")
