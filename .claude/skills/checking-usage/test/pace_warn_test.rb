#!/usr/bin/env ruby
# frozen_string_literal: true
# Tests for the sibling hook ../../../hooks/usage-pace-warn.rb, co-located here
# because it shares the per-session reconciliation with the checking-usage skill.
# Verifies it reconciles across per-session snapshots and never warns off a
# stale/expired reading, and that the context check is strictly session-local.
#
# Run: ruby .claude/skills/checking-usage/test/pace_warn_test.rb
require "json"
require "fileutils"
require "open3"

HOOK = File.expand_path("../../../hooks/usage-pace-warn.rb", __dir__)

$fails = 0
def check(name, cond)
  puts(cond ? "  ok   #{name}" : "  FAIL #{name}")
  $fails += 1 unless cond
end

def with_tmp
  dir = "/tmp/pace_warn_test_#{Process.pid}_#{rand(100_000)}"
  FileUtils.mkdir_p(dir)
  yield dir
ensure
  FileUtils.rm_rf(dir)
end

def snap(dir, sid, hash)
  File.write(File.join(dir, "usage-cache-#{sid}.json"), JSON.generate(hash))
end

def run_hook(dir, session_id:, event: "UserPromptSubmit")
  env = { "USAGE_CACHE" => File.join(dir, "usage-cache.json"), "TMPDIR" => dir }
  payload = JSON.generate("hook_event_name" => event, "session_id" => session_id)
  out, _err, st = Open3.capture3(env, "ruby", HOOK, stdin_data: payload)
  [out, st.exitstatus]
end

now = Time.now.to_i

puts "TEST 1: weekly pace warn uses reconciled current-window max, ignores expired-window 95%"
with_tmp do |dir|
  wk_reset = now + 4 * 86_400   # day 3/7 -> allowance ~43%
  cur5h    = now + 3600
  snap(dir, "a", "rate_limits" => { "seven_day" => { "used_percentage" => 70, "resets_at" => wk_reset },
                                    "five_hour" => { "used_percentage" => 10, "resets_at" => cur5h } },
                 "captured_at" => now - 3, "session_id" => "a")
  # a session frozen on an EXPIRED weekly window reporting a scary 95% -- must be dropped
  snap(dir, "b", "rate_limits" => { "seven_day" => { "used_percentage" => 95, "resets_at" => now - 86_400 } },
                 "captured_at" => now - 4, "session_id" => "b")
  out, code = run_hook(dir, session_id: "a")
  check("exit 0", code == 0)
  check("warns on weekly pace", out.include?("WEEKLY pace"))
  check("uses reconciled 70%, not expired 95%", out.include?("70% used") && !out.include?("95%"))
end

puts "TEST 2: 5h session warn uses current window (88%), not an expired 99%"
with_tmp do |dir|
  cur5h = now + 1800
  snap(dir, "a", "rate_limits" => { "five_hour" => { "used_percentage" => 88, "resets_at" => cur5h },
                                    "seven_day" => { "used_percentage" => 20, "resets_at" => now + 4 * 86_400 } },
                 "captured_at" => now - 2, "session_id" => "a")
  snap(dir, "z", "rate_limits" => { "five_hour" => { "used_percentage" => 99, "resets_at" => now - 3600 } },
                 "captured_at" => now - 2, "session_id" => "z")
  out, _code = run_hook(dir, session_id: "a")
  check("warns on session", out.include?("5h SESSION window at 88%"))
  check("does not echo expired 99%", !out.include?("99%"))
  check("no 'resets in now'", !out.include?("resets in now"))
end

puts "TEST 3: context warn is session-local -- only THIS session's own file"
with_tmp do |dir|
  wk = { "seven_day" => { "used_percentage" => 10, "resets_at" => now + 4 * 86_400 } }
  snap(dir, "me",    "rate_limits" => wk, "captured_at" => now - 2, "session_id" => "me",
                     "context_window" => { "used_percentage" => 91, "context_window_size" => 1_000_000 })
  snap(dir, "other", "rate_limits" => wk, "captured_at" => now - 2, "session_id" => "other",
                     "context_window" => { "used_percentage" => 99, "context_window_size" => 1_000_000 })
  out, _code = run_hook(dir, session_id: "me")
  check("warns for own 91% context", out.include?("this session is at 91%"))
  check("does not warn off other session's 99%", !out.include?("99%"))

  out2, _code = run_hook(dir, session_id: "ghost")
  check("no context warn when caller has no own snapshot", !out2.include?("auto-compaction"))
end

puts "TEST 4: no snapshots -> silent, exit 0"
with_tmp do |dir|
  out, code = run_hook(dir, session_id: "a")
  check("exit 0 + no output", code == 0 && out.strip.empty?)
end

puts "TEST 5: stale account (old captures) -> no weekly/session warn"
with_tmp do |dir|
  snap(dir, "a", "rate_limits" => { "seven_day" => { "used_percentage" => 80, "resets_at" => now + 4 * 86_400 },
                                    "five_hour" => { "used_percentage" => 90, "resets_at" => now + 3600 } },
                 "captured_at" => now - 7200, "session_id" => "a")  # 2h old > STALE_SECS(1h)
  out, code = run_hook(dir, session_id: "a")
  check("silent on stale account", code == 0 && out.strip.empty?)
end

puts
puts($fails.zero? ? "ALL PASS" : "#{$fails} FAILURE(S)")
exit($fails.zero? ? 0 : 1)
