#!/usr/bin/env ruby
# frozen_string_literal: true
# Tests for the per-session-cache reconciliation in usage.rb + Burn.envelope.
# Reproduces the live scenario that motivated the fix: many concurrent sessions
# each mirror an ACCOUNT-GLOBAL rate-limit snapshot frozen at their own last API
# turn, so a naive single-cache read returns a foreign/stale session's numbers
# (an already-expired 5h window showing "resets now", or an under-counted weekly).
# The reader must instead reconcile to account truth.
#
# Run: ruby .claude/skills/checking-usage/test/reconcile_test.rb
require "json"
require "fileutils"
require "open3"

SKILL_PATH = File.expand_path("../usage.rb", __dir__)
BURN_PATH  = File.expand_path("../burn.rb", __dir__)

$fails = 0
def check(name, cond)
  puts(cond ? "  ok   #{name}" : "  FAIL #{name}")
  $fails += 1 unless cond
end

def with_tmp
  dir = "/tmp/reconcile_test_#{Process.pid}_#{rand(100_000)}"
  FileUtils.mkdir_p(dir)
  yield dir
ensure
  FileUtils.rm_rf(dir)
end

def write_snap(dir, sid, fh_used:, fh_reset:, wk_used:, wk_reset:, cap:)
  payload = {
    "session_id"  => sid,
    "captured_at" => cap,
    "rate_limits" => {
      "five_hour" => { "used_percentage" => fh_used, "resets_at" => fh_reset },
      "seven_day" => { "used_percentage" => wk_used, "resets_at" => wk_reset }
    }
  }
  File.write(File.join(dir, "usage-cache-#{sid}.json"), JSON.generate(payload))
end

def run_skill(dir)
  env = {
    "USAGE_CACHE"   => File.join(dir, "usage-cache.json"),
    "USAGE_HISTORY" => File.join(dir, "history.jsonl")
  }
  out, err, st = Open3.capture3(env, "ruby", SKILL_PATH)
  [out, err, st.exitstatus]
end

now = Time.now.to_i

# ---------------------------------------------------------------------------
puts "TEST 1: fresh + stale sessions -> recover current window (wk 42, ses 11)"
with_tmp do |dir|
  cur_reset = now + 225 * 60      # current 5h window, ~3.75h ahead
  wk_reset  = now + 4 * 86_400
  write_snap(dir, "fresh1", fh_used: 11, fh_reset: cur_reset, wk_used: 42, wk_reset: wk_reset, cap: now - 5)
  write_snap(dir, "fresh2", fh_used: 11, fh_reset: cur_reset, wk_used: 42, wk_reset: wk_reset, cap: now - 3)
  write_snap(dir, "fresh3", fh_used: 2,  fh_reset: cur_reset, wk_used: 40, wk_reset: wk_reset, cap: now - 18)
  # idle sessions holding EXPIRED 5h windows + under-counted weekly (the bug source)
  write_snap(dir, "stale1", fh_used: 31, fh_reset: now - 75 * 60,  wk_used: 39, wk_reset: wk_reset, cap: now - 7)
  write_snap(dir, "stale2", fh_used: 17, fh_reset: now - 375 * 60, wk_used: 33, wk_reset: wk_reset, cap: now - 15)

  out, _err, code = run_skill(dir)
  check("exit 0", code == 0)
  check("SESSION 11% (current window, not 31)", out.match?(/SESSION\s+11% used/))
  check("does NOT report the expired 31%", !out.include?("31% used"))
  check("SESSION does not say 'resets in now'", !out.match?(/SESSION.*resets in now/m))
  check("WEEKLY 42% (max across sessions, not 33/39)", out.match?(/WEEKLY\s+42% used/))
  check("fresh (age from newest render)", out.match?(/data\s+fresh/))
  check("verdict KEEP GOING", out.include?("KEEP GOING"))
end

# ---------------------------------------------------------------------------
puts "TEST 2: run 'outside a session' -> same reconciliation (no own session needed)"
with_tmp do |dir|
  cur_reset = now + 120 * 60
  wk_reset  = now + 3 * 86_400
  write_snap(dir, "other1", fh_used: 8, fh_reset: cur_reset, wk_used: 55, wk_reset: wk_reset, cap: now - 4)
  write_snap(dir, "other2", fh_used: 8, fh_reset: cur_reset, wk_used: 54, wk_reset: wk_reset, cap: now - 9)
  out, _err, code = run_skill(dir)
  check("exit 0", code == 0)
  check("WEEKLY 55%", out.match?(/WEEKLY\s+55% used/))
  check("SESSION 8%", out.match?(/SESSION\s+8% used/))
end

# ---------------------------------------------------------------------------
puts "TEST 3: all 5h windows expired -> honest unknown, weekly still works"
with_tmp do |dir|
  wk_reset = now + 2 * 86_400
  write_snap(dir, "idleA", fh_used: 40, fh_reset: now - 30 * 60, wk_used: 60, wk_reset: wk_reset, cap: now - 3)
  write_snap(dir, "idleB", fh_used: 22, fh_reset: now - 90 * 60, wk_used: 58, wk_reset: wk_reset, cap: now - 6)
  out, _err, code = run_skill(dir)
  check("exit 0", code == 0)
  check("SESSION reported as no live 5h window", out.include?("no live 5h window"))
  check("does NOT echo expired 40%", !out.include?("40% used"))
  check("WEEKLY still 60%", out.match?(/WEEKLY\s+60% used/))
end

# ---------------------------------------------------------------------------
puts "TEST 4: no snapshots at all -> exit 2, 'not rendered' message"
with_tmp do |dir|
  _out, err, code = run_skill(dir)
  check("exit 2", code == 2)
  check("says 'no interactive window has drawn'", err.include?("no interactive Claude Code window has drawn"))
end

# ---------------------------------------------------------------------------
puts "TEST 4b: snapshots present but ALL corrupt -> exit 2, 'unreadable' message"
with_tmp do |dir|
  File.write(File.join(dir, "usage-cache-corrupt.json"), "{not json at all")
  _out, err, code = run_skill(dir)
  check("exit 2", code == 2)
  check("says corrupt/unreadable, not 'open a window'",
        err.include?("none is readable") && !err.include?("no interactive Claude Code window has drawn"))
end

# ---------------------------------------------------------------------------
puts "TEST 5: Burn.envelope collapses interleaved sessions to a monotonic climb"
require BURN_PATH
wk_reset = now + 4 * 86_400
# Session A climbing 30->32 interleaved with idle session B frozen at 25.
raw = [
  { "t" => now - 3600, "wk" => 30, "wk_reset" => wk_reset, "session" => "A" },
  { "t" => now - 3300, "wk" => 25, "wk_reset" => wk_reset, "session" => "B" },
  { "t" => now - 3000, "wk" => 31, "wk_reset" => wk_reset, "session" => "A" },
  { "t" => now - 2700, "wk" => 25, "wk_reset" => wk_reset, "session" => "B" },
  { "t" => now - 2400, "wk" => 32, "wk_reset" => wk_reset, "session" => "A" }
]
env = Burn.envelope(raw, "wk", "wk_reset")
wks = env.map { |e| e["wk"] }
check("envelope is monotonic non-decreasing", wks.each_cons(2).all? { |a, b| b >= a })
check("envelope ends at running max 32", wks.last == 32)
check("envelope never dips to the stale 25", !wks.include?(25))
check("nil in -> nil out (unreadable propagates)", Burn.envelope(nil, "wk", "wk_reset").nil?)

# older-window samples dropped / newer window restarts the running max
raw2 = raw + [{ "t" => now - 100, "wk" => 5, "wk_reset" => wk_reset + 999, "session" => "C" }]
env2 = Burn.envelope(raw2, "wk", "wk_reset")
check("newer window resets the envelope", env2.last["wk"] == 5 && env2.last["wk_reset"] == wk_reset + 999)

# a schema-drifted line with a non-numeric reset must NOT crash the ordering
raw3 = raw + [{ "t" => now - 50, "wk" => 99, "wk_reset" => "oops", "session" => "D" }]
begin
  env3 = Burn.envelope(raw3, "wk", "wk_reset")
  check("non-numeric reset does not raise (fail-quiet preserved)", true)
  check("corrupt-reset row excluded from envelope", env3.none? { |e| e["wk"] == 99 })
rescue StandardError => e
  check("non-numeric reset does not raise (fail-quiet preserved) [#{e.class}]", false)
end

puts
puts($fails.zero? ? "ALL PASS" : "#{$fails} FAILURE(S)")
exit($fails.zero? ? 0 : 1)
