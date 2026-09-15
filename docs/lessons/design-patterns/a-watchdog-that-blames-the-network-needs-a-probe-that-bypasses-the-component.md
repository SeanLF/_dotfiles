---
title: A watchdog that blames the network needs a probe that bypasses the component, or a stale component hides behind the network label
date: 2026-09-14
category: design-patterns
module: bin/nextdns-watch
problem_type: silent_noop
severity: medium
applies_when:
  - A health check has a "not our fault, it's upstream" branch that deliberately does nothing
  - A daemon holds long-lived connections (HTTP/2, gRPC, DoH) across Wi-Fi or VPN changes
  - You are classifying a failure by which probe failed and one probe passes through the component under suspicion
  - Comparing two snapshots where one side is a handle that re-fetches live state
tags:
  [
    watchdog,
    health-check,
    nextdns,
    dns,
    doh,
    network-change,
    http2,
    stale-connection,
    probe-design,
  ]
---

## The lesson

A watchdog can only refuse to act on "the network is down" if it has measured the
network without going through the component it is watching. A probe that reaches
the upstream **via** the daemon cannot tell "upstream unreachable" from "daemon
holds a dead connection to the upstream"; both look identical, and the safe-sounding
"NOT restarting, this is the network" branch silently covers the one failure a
restart would fix.

## What happened

Six manual switches between a home router and a phone hotspot each wedged DNS for
6 to 35 s. The NextDNS daemon listened fine (the /etc/hosts probe passed) but its
upstream probe failed, so the watchdog logged `NET ... NOT restarting` and waited.
Meanwhile `dig @1.1.1.1` answered in 30 ms. The daemon was the problem:

- Its network-change detector polls `net.Interfaces()` every 10 s and diffs names,
  flags and addresses. Addresses are read with `Interface.Addrs()`, which is a live
  kernel lookup, so old and new are always equal. Address-only changes, which is what
  every Wi-Fi network switch is, are invisible. Seven address changes that day, zero
  detections; three interface add/removes, three detections. Adding and removing a
  `lo0` alias reproduced it.
- Undetected, the HTTP/2 connection to the old source address stayed the active
  transport. Each query burned the 5 s timeout, and only the tenth consecutive failure
  triggered a re-test. Ten failures at low query volume took 32 s.

A restart replaced the dead connection in about a second. The Raycast "Fix DNS"
script had been doing exactly that by hand.

## Guidance

Add the third probe. Listener OK, upstream-through-daemon failing, upstream-direct OK
means the daemon is stale: heal it with the same bounded restart path as a wedged
listener (threshold, cooldown, max heals). Upstream-direct failing too still means the
network, and that branch stays a no-op. The direct probe's own failure mode is safe:
if a VPN blocks plain DNS to 1.1.1.1 the watchdog falls back to the old behaviour,
it never restarts on a false positive.

Two shapes to recognise elsewhere:

1. **Every "not our fault" branch needs its own evidence.** If the branch is reached
   by elimination rather than by a probe that measured the blamed party, it is a
   default, not a diagnosis.
2. **A diff of live-lookup values compares the present with the present.** Snapshot
   the data, not a handle that re-fetches it. The netstatus bug above is this shape;
   so is comparing two `os.Stat` results by re-calling `Stat`.

## Related

- [[a-passing-test-may-be-asserting-nothing]]: the test for the new branch was
  mutation-checked by disabling the direct probe; 3 of 8 assertions failed. The
  branch shipped and was retired the same night when the Mac moved to Tailscale
  DNS (docs/dns-resolver.md); the lesson outlives the code.
- [[a-reachability-test-must-pin-the-address-family]]: the direct probe pins a v4
  resolver for the same reason.
- Upstream: nextdns/nextdns `netstatus/netstatus.go` `diff()`, unchanged on master as
  of 2026-09-14. Not yet reported.
