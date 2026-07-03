#!/usr/bin/env ruby
# frozen_string_literal: true

# Claude Code status line -- usage gauge (session + weekly budget).
#
# The bar is monochrome by design: information is carried by shape and texture,
# which read even where colour doesn't.
#   solid block  = budget used and on pace
#   hatch block  = budget used but PAST the on-pace line (burning too fast)
#   light shade  = remaining
# When you're within pace the bar is clean solid; an over-pace tail turns rough.
# The weekly bar widens with the terminal (COLUMNS) for finer resolution.
#
# Colour (ANSI, officially supported -- code.claude.com/docs/en/statusline) is
# used ONLY as an escalation signal on the numbers: healthy values stay plain so
# the line reads calm, and go yellow -> bright red as a window nears its limit.
# Bright red (91) not dark red (31), which is near-invisible on dark terminals.
#
# It fails quiet (degrades to blank) so it never dumps a stack trace into the
# bar -- but anomalies are recorded in LOG, so a Claude Code payload change can't
# silently break the gauge with no trace. Watch it with:
#   tail -f ~/.claude/statusline.log
require "json"
require "time"

EIGHTHS = [" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"].freeze
SOLID   = "█"  # used, on pace
HATCH   = "▓"  # used, past the on-pace line
TRACK   = "░"  # remaining
RESET   = "\e[0m"
YELLOW  = "\e[93m"
RED     = "\e[91m"  # bright, so it stays legible on dark backgrounds
BOLD    = "\e[1m"   # paired with RED for the loudest tier (cache critical/cold)
SEP     = " \e[2m·\e[22m "  # faint dot between timescale groups (recedes; content pops)
WEEK    = 7 * 86_400  # seconds in the seven_day window
# Claude Code caches the whole conversation and, on a Claude subscription, requests
# the 1h prompt-cache TTL (verified: usage.cache_creation shows ephemeral_1h). Each
# turn refreshes it; idle past the TTL makes the NEXT message re-send the entire
# prefix uncached (~2x write vs ~0.1x read) -- very expensive on a long conversation,
# and Claude Code gives NO warning (its docs point you to a status line instead). We
# surface the countdown ONLY as it runs low. The live TTL is DETECTED from the
# transcript's cache buckets (CC drops 1h -> 5m once you're on paid usage credits);
# CACHE_TTL is only the fallback when detection can't read a bucket. NB the countdown
# only stays live while idle if the status line has a refreshInterval set (otherwise
# it freezes at the last render); see settings.json.
CACHE_TTL  = (ENV["USAGE_CACHE_TTL_SECS"]  || "3600").to_i  # fallback when TTL undetectable
CACHE_WARN = (ENV["USAGE_CACHE_WARN_SECS"] || "900").to_i   # show the segment once under this
CACHE_CRIT = (ENV["USAGE_CACHE_CRIT_SECS"] || "180").to_i   # bold red (not yellow) under this
LOG     = File.expand_path(ENV["STATUSLINE_LOG"] || "~/.claude/statusline.log")
# The live rate-limit payload only ever reaches this status line process; nothing
# else on the machine can see it on demand. So we mirror it to a cache file every
# render -- the `checking-usage` skill reads this to answer "how much budget is
# left?" mid-session. captured_at lets the reader reject stale data.
CACHE   = File.expand_path(ENV["USAGE_CACHE"] || "~/.claude/usage-cache.json")
# Append-only log of weekly/session % over time, one JSON line per CHANGE. The
# cache is a single latest-snapshot; this is the series the checking-usage reader
# turns into a burn rate ("weekly hits the cap in ~Xh"). Deduped so the constant
# re-renders don't spam it -- a sample lands only when a number actually moves.
HISTORY = File.expand_path(ENV["USAGE_HISTORY"] || "~/.claude/rate-limit-history.jsonl")
# Subscription tier is NOT in the hook payload (can't be auto-detected), so it's set
# here and updated by hand on a plan change. Stamped into each history sample so a
# reader can turn weekly-% into a tier-relative cost. See _dotfiles/docs/usage-economics.md.
TIER = (ENV["USAGE_TIER"] || "max_20x").freeze

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

# Last-activity time AND the active prompt-cache TTL, both from the transcript's
# tail (read big enough to catch a full turn without slurping a multi-MB file on
# the hot render path; a rare >32KB final message just yields nil -> segment hidden).
# We DETECT the TTL rather than guess: Claude Code writes each turn's cache increment
# to the ephemeral_1h or ephemeral_5m bucket depending on which TTL is in force (1h
# on a subscription, 5m once you're on paid usage credits), so the buckets are the
# ground truth. => [epoch, ttl_or_nil]; ttl nil when undetectable (caller falls back
# to CACHE_TTL). nil overall when there's no usable timestamp.
def cache_state(path)
  return nil unless path.is_a?(String) && File.exist?(path)

  tail = File.open(path, "rb") do |f|
    f.seek([f.size - 32_768, 0].max)
    f.read
  end
  lines = tail.to_s.lines
  lines.shift if tail.bytesize >= 32_768 && lines.size > 1  # drop the boundary-cut fragment
  entries = lines.filter_map do |l|
    obj = JSON.parse(l) rescue nil
    obj if obj.is_a?(Hash)
  end

  ts_entry = entries.reverse_each.find { |e| e["timestamp"].is_a?(String) }
  unless ts_entry
    # Content present but no timestamp -> a field rename would silently kill the
    # (hidden) cache warning, so log it like the file's other drift guards.
    log("warn", "transcript tail has no parseable timestamp entry") unless entries.empty?
    return nil
  end

  ts = begin
    Time.parse(ts_entry["timestamp"]).to_i  # ISO8601 w/ zone -> correct epoch
  rescue ArgumentError => e
    log("warn", "transcript timestamp unparseable: #{e.message}")
    return nil
  end

  # Newest turn that wrote to a cache bucket decides the TTL; older turns share it
  # unless the credit state flipped mid-session (then the newest is what's live).
  ttl = nil
  entries.reverse_each do |e|
    msg = e["message"]
    usg = msg["usage"] if msg.is_a?(Hash)          # type-guarded nav (no dig) so a
    cc  = usg["cache_creation"] if usg.is_a?(Hash) # non-Hash message can't raise
    next unless cc.is_a?(Hash)

    if cc["ephemeral_5m_input_tokens"].to_i.positive?
      ttl = 300
      break
    elsif cc["ephemeral_1h_input_tokens"].to_i.positive?
      ttl = 3600
      break
    end
  end
  [ts, ttl]
rescue StandardError
  nil  # transient IO (deleted mid-read, perms) -> omit, expected, don't spam the log
end

# Compact token count for a context-window size: 1000000 -> "1M", 200000 -> "200k".
def fmt_size(n)
  return nil unless n.is_a?(Numeric) && n.positive?

  n >= 1_000_000 ? "#{(n / 1_000_000.0).round}M" : "#{(n / 1000.0).round}k"
end

# Escalation colour for a percentage: plain when healthy, yellow past `warn`,
# bright red past `crit`. Only the passed text is wrapped, so layout is unaffected
# (the ANSI bytes add no display width, and the bar sizing never measures these).
def sev(text, pct, warn:, crit:)
  return "#{RED}#{text}#{RESET}" if pct >= crit
  return "#{YELLOW}#{text}#{RESET}" if pct >= warn

  text
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

# Last recorded history entry, read from the file's tail so this stays O(1) as the
# log grows (never slurp the whole file on the hot render path). nil if none/garbled.
def last_history_entry
  return nil unless File.exist?(HISTORY)

  tail = File.open(HISTORY, "rb") do |f|
    f.seek([f.size - 512, 0].max)
    f.read
  end
  line = tail.to_s.lines.map(&:strip).reject(&:empty?).last
  line && JSON.parse(line)
rescue StandardError
  nil  # a bad tail just means "no usable last entry" -> we'll append a fresh one
end

# Append one weekly/session sample, but only when weekly % or its window changed
# since the last sample (renders are constant; we want a point per real move).
# Append-only single-line writes are atomic across the concurrent windows that all
# render this bar, so no locking. rate_limits is account-global, so every window
# records the same series -- dedup makes the duplicates harmless.
#
# We also stamp tier + the rendering session's cumulative cost so a reader can turn
# weekly-% into a tier-relative dollar figure. Caveats: `tier` is a manual constant;
# `cost` is that ONE session's running total_cost_usd (tagged by `session`), NOT the
# weekly cross-session total -- ccusage stays authoritative for spend. And because
# dedup keys on wk only across all concurrent sessions, the first to reach a given
# wk% wins that sample, so any one session's cost slice is sparse.
def record_history(rl, data, now)
  sd = rl["seven_day"]
  return unless sd.is_a?(Hash) && sd["used_percentage"].is_a?(Numeric)

  entry = { "t" => now, "wk" => sd["used_percentage"], "wk_reset" => sd["resets_at"] }
  fh = rl["five_hour"]
  entry["ses"] = fh["used_percentage"] if fh.is_a?(Hash) && fh["used_percentage"].is_a?(Numeric)

  entry["tier"] = TIER
  if data.is_a?(Hash)
    cost = data["cost"]
    entry["cost"] = cost["total_cost_usd"] if cost.is_a?(Hash) && cost["total_cost_usd"].is_a?(Numeric)
    entry["session"] = data["session_id"] if data["session_id"].is_a?(String)
  end

  last = last_history_entry
  return if last && last["wk"] == entry["wk"] && last["wk_reset"] == entry["wk_reset"]

  File.open(HISTORY, "a") { |f| f.write("#{JSON.generate(entry)}\n") }
rescue StandardError => e
  log("warn", "history append failed: #{e.class}: #{e.message}")
end

# Segments grouped by timescale so the line has a logical progression: what's
# happening now (context) -> this session (5h) -> this week (7d). The elastic
# weekly bar sits last, which also keeps the fixed-width groups at stable left
# positions instead of shifting with COLUMNS.
now_grp = []  # this conversation (context window)
ses_grp = []  # 5h rolling session
wk_grp  = []  # 7d weekly pool
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
  record_history(rl, data, now)

  fh = rl["five_hour"]
  if typed?(rl, "five_hour", Hash, "five_hour") && typed?(fh, "used_percentage", Numeric, "five_hour.used_percentage")
    ses = fh["used_percentage"].round
    seg = "ses #{sev("#{ses}%", ses, warn: 80, crit: 92)}"
    seg += " #{fmt_dur(fh['resets_at'] - now)}" if typed?(fh, "resets_at", Numeric, "five_hour.resets_at")
    ses_grp << seg
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
      pct  = ctx.round
      seg  = "ctx #{sev("#{pct}%", pct, warn: 70, crit: 90)}"
      size = fmt_size(cw["context_window_size"])
      seg += " #{size}" if size
      now_grp << seg
    else
      # Hash present but no derivable % -> inner keys renamed. Log it, like the
      # seven_day guard below, so a schema change can't drop the segment silently.
      log("warn", "context_window present but no derivable usage (keys: #{cw.keys.join(', ')})")
    end
  end

  # Prompt-cache countdown (session-local, own transcript). Shown ONLY as it nears
  # expiry -- fresh cache stays hidden, so no clutter or width cost in the common
  # case; it appears (yellow, then red under 3m, then "cold") when it's time to
  # send-to-keep-warm or accept the re-cache cost on the next message.
  if (st = cache_state(data["transcript_path"]))
    ts, ttl = st
    left = ts + (ttl || CACHE_TTL) - now
    if left <= 0
      now_grp << "cache #{BOLD}#{RED}cold#{RESET}"
    elsif left < CACHE_WARN
      col = left < CACHE_CRIT ? "#{BOLD}#{RED}" : YELLOW  # bold red is the loudest tier
      now_grp << "cache #{col}#{fmt_dur(left)}#{RESET}"
    end
  end

  sd = rl["seven_day"]
  if typed?(rl, "seven_day", Hash, "seven_day") && typed?(sd, "used_percentage", Numeric, "seven_day.used_percentage")
    used  = sd["used_percentage"]
    # Reserve enough columns for the surrounding text so the bar never pushes the
    # line past COLUMNS and wraps. Widest non-bar case -- everything at 100%, long
    # durations, both separators, AND the usually-hidden cache segment: "ctx 100%
    # 200k  cache cold · ses 100% 4h59m · wk  100% 6d23h  day 100%" -- is ~69 chars;
    # reserve 70. (On wide terminals the bar caps at 40 anyway, so this bites <110.)
    width = [[cols - 70, 40].min, 16].max
    # Threshold on the displayed (rounded) value so the colour never disagrees
    # with the number; hoisted so both branches share one 75/90 definition.
    wk = sev("#{used.round}%", used.round, warn: 75, crit: 90)
    if typed?(sd, "resets_at", Numeric, "seven_day.resets_at")
      reset     = sd["resets_at"]
      pace      = ((now - (reset - WEEK)).to_f / WEEK).clamp(0.0, 1.0)
      days_left = [(reset - now).to_f / 86_400, 0.0001].max
      day       = [100 - used, (100 - used) / days_left].min.clamp(0, 100)
      wk_grp << "wk #{meter(used / 100.0, pace, width)} #{wk} #{fmt_dur(reset - now)}"
      wk_grp << "day #{day.round}%"
    else
      wk_grp << "wk #{meter(used / 100.0, nil, width)} #{wk}"
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

# Display order = timescale progression; within a group, segments join tight
# (double-space), groups join on the faint separator. Empty groups drop out.
groups = [now_grp, ses_grp, wk_grp].reject(&:empty?).map { |g| g.join("  ") }
print groups.join(SEP)
