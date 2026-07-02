# frozen_string_literal: true

# Weekly burn-rate projection from the rate-limit history the status line records
# (~/.claude/rate-limit-history.jsonl, one JSON sample per change).
#
# Reset-robust by design. Anthropic resets the weekly window WITHOUT warning --
# model launches, rate-limit-counting fixes, incidents -- so resets_at is not
# trustworthy as the only reset signal. Instead we treat any DROP in weekly %
# (or a change of reset window) as a reset boundary and measure burn only over
# the current monotonic run since the last boundary. A surprise reset can never
# produce a phantom "negative burn" or a doom projection: it just restarts the
# clock. Flat or just-reset history yields nil (no burn to project), not a guess.
#
# Fail-soft but not fail-silent: read() never raises, and it distinguishes an
# UNREADABLE/garbled history (returns nil) from a merely absent/empty one
# (returns []). The caller surfaces the former instead of quietly acting as if
# there's simply no burn -- a dead projection must not masquerade as "all clear".
require "json"

module Burn
  module_function

  # => Array of recent, well-formed samples (chronological); [] when there's no
  # history yet; nil when the file exists with content but nothing parses (schema
  # drift / corruption) or can't be read at all. Never raises.
  def read(path, now, keep_secs: 14 * 86_400)
    return [] unless File.exist?(path)

    raw = File.readlines(path)
    parsed = raw.filter_map { |l| parse(l) }
    # Content present but not a single usable line -> drift/corruption, not warmup.
    return nil if parsed.empty? && raw.any? { |l| !l.strip.empty? }

    parsed.select { |e| e["t"] >= now - keep_secs }.sort_by { |e| e["t"] }
  rescue StandardError
    nil  # I/O error (EACCES, EISDIR, bad encoding...) -> unreadable, signal it
  end

  def parse(line)
    e = JSON.parse(line)
    e if e.is_a?(Hash) && e["t"].is_a?(Numeric) && e["wk"].is_a?(Numeric)
  rescue StandardError
    nil  # a bad line is dropped, not fatal; read() flags an all-bad file as nil
  end

  # The longest trailing run that is non-decreasing in weekly % AND shares one
  # reset window -- i.e. everything since the most recent reset boundary.
  def current_run(entries)
    return entries if entries.size < 2

    start = entries.size - 1
    (entries.size - 1).downto(1) do |i|
      cur = entries[i]
      prev = entries[i - 1]
      break if cur["wk"] < prev["wk"]                # weekly fell -> a reset landed here
      break if cur["wk_reset"] != prev["wk_reset"]   # window changed -> new week

      start = i - 1
    end
    entries[start..]
  end

  # Average %/hour over the current run and the resulting time-to-cap.
  # `entries` comes from read(). => { burn_per_h:, hours_to_cap:, wk: } or nil
  # when there isn't enough signal (no entries, flat, or just reset).
  def project(entries)
    return nil unless entries && entries.size >= 2

    run = current_run(entries)
    return nil if run.size < 2

    first = run.first
    last = run.last
    dt_h = (last["t"] - first["t"]) / 3600.0
    dpct = last["wk"] - first["wk"]
    return nil if dt_h <= 0 || dpct <= 0            # flat / just reset: nothing to project

    burn = dpct / dt_h
    { burn_per_h: burn, hours_to_cap: (100.0 - last["wk"]) / burn, wk: last["wk"] }
  end
end
