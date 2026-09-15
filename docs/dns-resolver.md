# DNS resolver on the Mac: Tailscale DNS, not the NextDNS CLI

Decided 2026-09-15. Stale by default; re-check the numbers before relying on them.

## Decision

The Mac accepts Tailscale's DNS settings (`tailscale set --accept-dns=true`).
Tailscale's resolver at 100.100.100.100 answers MagicDNS itself and forwards
everything else to NextDNS over DoH under the profile the tailnet policy assigns
to the device. The NextDNS CLI, its watchdog, the Tailscale search-domain
daemon, and their sudoers grants are gone.

Tailnet policy: global nameserver NextDNS 8c9b3f "Personal" with Override DNS on;
`nextdns:38ba9e` ("Hetzner Server", allowlists sentry.io) on `tag:server`,
carried by seanfloyd-hetzner only. raspberrypi and parents-macbookair run
`accept-dns=false` by choice. GL-MT3000 keeps GL.iNet's stubby DoT on its own
account's profile 85c61c and Tailscale DNS off.

## Why

The CLI's network-change detector compares live address lookups against
themselves, so a Wi-Fi network switch (address-only change) is invisible. The
daemon keeps its HTTPS connection to the old address; each query burns the 5 s
timeout and only the tenth consecutive failure triggers re-selection. Measured
on 2026-09-14: six manual switches, 6 to 35 s of unresolvable uncached names
each. Side by side on 2026-09-15 00:38, home to hotspot and back: Tailscale
answered every sample; the CLI failed 5 s on the way out and did not recover on
the way back in over three minutes.

Tailscale detects changes through the route socket and closes idle DoH
connections after 10 s, so a dead connection costs at most one query.

## Cost, measured

|                                                            |                                                      |
| ---------------------------------------------------------- | ---------------------------------------------------- |
| uncached lookup, anycast edge vs the CLI's unicast Toronto | +9 ms median, +30 ms p95 (353 samples)               |
| first lookup after 10 s of DNS silence, TLS reconnect      | about +350 ms, seen in 1 of 3 timed rounds           |
| 40 concurrent fresh lookups                                | 129 to 240 ms wall, one HTTP/2 connection            |
| second cache layer                                         | gone; mDNSResponder still caches, repeats about 3 ms |

## What the CLI did that this does not

- Filter while Tailscale is disconnected. Disconnected at home falls back to
  the router, which is NextDNS anyway; on a hotspot it is the carrier's DNS.
- Captive portals: turn Tailscale DNS off (Raycast "Toggle DNS"), log in, back
  on. Upstream has detection since 1.72 and no bypass; PR 13430 (2024) and the
  July 2026 refactor into `feature/captiveportal` are the reference points.
- ProtonVPN: its custom-DNS check cannot reach 100.100.100.100 through its own
  tunnel and falls back to Proton's resolver. Untested fix: exclude that IP in
  Proton's split tunnelling.

## Revert

Reinstall the CLI (`sh -c "$(curl -sL https://nextdns.io/install)"` or from
source), `sudo nextdns install -profile 8c9b3f -forwarder
tail739266.ts.net.=100.100.100.100 -cache-size 10MB`, `sudo nextdns activate`,
`tailscale set --accept-dns=false`. The watchdog and search-domain daemon are in
git history before this commit.

## Related

- docs/lessons/design-patterns/a-watchdog-that-blames-the-network-needs-a-probe-that-bypasses-the-component.md
- tests/probe-dns-race.sh reproduces the side-by-side measurement.
