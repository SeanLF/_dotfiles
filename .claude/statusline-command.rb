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
# The live rate-limit payload only ever reaches this status line process; nothing
# else on the machine can see it on demand. So we mirror it to a cache file every
# render -- the `checking-usage` skill reads this to answer "how much budget is
# left?" mid-session. captured_at lets the reader reject stale data.
CACHE   = File.expand_path(ENV["USAGE_CACHE"] || "~/.claude/usage-cache.json")

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

# Compact token count for a context-window size: 1000000 -> "1M", 200000 -> "200k".
def fmt_size(n)
  return nil unless n.is_a?(Numeric) && n.positive?

  n >= 1_000_000 ? "#{(n / 1_000_000.0).round}M" : "#{(n / 1000.0).round}k"
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

# Mirror the WHOLE hook payload (plus captured_at) for out-of-band readers like
# the checking-usage skill -- so any field can be used later, not just the ones
# the bar happens to draw.
#
# Global vs session-local is the thing to get right: rate_limits is ACCOUNT-GLOBAL
# (same in every window) and safe to trust across sessions; everything else
# (context_window, cost, model, cwd...) is SESSION-LOCAL and reflects whichever
# window rendered LAST. The payload's session_id rides along as the discriminator:
# a reader may trust rate_limits unconditionally, but must match session_id before
# treating any session-local field as its own (else read that session's jsonl).
#
# Only writes when rate_limits is present. Early in a session (before the first
# API response) the payload has no rate_limits; writing then would overwrite the
# last-known-good global budget with a blank and stamp it fresh, silently blinding
# the reader. Skipping preserves the prior cache. Fail-quiet: a write error must
# never disturb the bar.
def cache_usage(data, now)
  return unless data.is_a?(Hash) && data["rate_limits"].is_a?(Hash) && !data["rate_limits"].empty?

  tmp = "#{CACHE}.#{Process.pid}.tmp"
  File.write(tmp, JSON.generate(data.merge("captured_at" => now)))
  File.rename(tmp, CACHE)  # atomic swap so a concurrent reader never sees a half-written file
rescue StandardError => e
  log("warn", "usage cache write failed: #{e.class}: #{e.message}")
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

  cache_usage(data, now)

  fh = rl["five_hour"]
  if typed?(rl, "five_hour", Hash, "five_hour") && typed?(fh, "used_percentage", Numeric, "five_hour.used_percentage")
    seg = "ses #{fh['used_percentage'].round}%"
    seg += " #{fmt_dur(fh['resets_at'] - now)}" if typed?(fh, "resets_at", Numeric, "five_hour.resets_at")
    parts << seg
  end

  # Context window fill -- the fastest-moving, most-glanced signal (drives
  # compaction), and absent from Claude Code's own bar. used_percentage is on
  # recent builds; older ones give only token counts, so derive as a fallback.
  # It rides along in the cache (whole payload is mirrored) but is SESSION-LOCAL:
  # a cross-session reader must not treat it as its own window's usage.
  cw = data["context_window"]
  if typed?(data, "context_window", Hash, "context_window")
    ctx =
      if cw["used_percentage"].is_a?(Numeric)
        cw["used_percentage"].to_f
      elsif cw["total_input_tokens"].is_a?(Numeric) && cw["context_window_size"].is_a?(Numeric) && cw["context_window_size"].positive?
        cw["total_input_tokens"].to_f / cw["context_window_size"] * 100
      end
    if ctx
      seg  = "ctx #{ctx.round}%"
      size = fmt_size(cw["context_window_size"])
      seg += " #{size}" if size
      parts << seg
    else
      # Hash present but no derivable % -> inner keys renamed. Log it, like the
      # seven_day guard below, so a schema change can't drop the segment silently.
      log("warn", "context_window present but no derivable usage (keys: #{cw.keys.join(', ')})")
    end
  end

  sd = rl["seven_day"]
  if typed?(rl, "seven_day", Hash, "seven_day") && typed?(sd, "used_percentage", Numeric, "seven_day.used_percentage")
    used  = sd["used_percentage"]
    # Reserve enough columns for the surrounding text so the bar never pushes the
    # line past COLUMNS and wraps. Widest non-bar case -- everything at 100% with
    # long durations, "ses 100% 4h59m  ctx 100% 200k  wk  100% 6d23h  day 100%" --
    # is ~55 chars; reserve 56 for a column of slack. (On wide terminals the bar
    # is capped at 40 anyway, so this only bites below ~96 cols.)
    width = [[cols - 56, 40].min, 16].max
    if typed?(sd, "resets_at", Numeric, "seven_day.resets_at")
      reset     = sd["resets_at"]
      pace      = ((now - (reset - WEEK)).to_f / WEEK).clamp(0.0, 1.0)
      days_left = [(reset - now).to_f / 86_400, 0.0001].max
      day       = [100 - used, (100 - used) / days_left].min.clamp(0, 100)
      parts << "wk #{meter(used / 100.0, pace, width)} #{used.round}% #{fmt_dur(reset - now)}"
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
