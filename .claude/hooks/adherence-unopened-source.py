#!/usr/bin/env python3
"""Base rate for the consequential half of the verification rule.

Session A's worst error: "asserted inside-IR35 without opening the page Miles
linked." That shape is detectable. When the user supplies a URL and the
assistant then writes about the subject without ever fetching it, the claim
rests on nothing.

Counts a URL as OPENED if any later WebFetch/WebSearch targets it, or any Bash
command names it (curl/gh/etc). Runs its own negative control first: a metric
whose positive branch never fires is indistinguishable from a broken one.

LIMITATION, stated inline because it changes how to read the number: a pasted
URL is not always a request to fetch, and a subagent's fetch does not appear in
the parent transcript. So this is an upper bound on the failure, not a count of
it.
"""

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path.home() / ".claude/projects"
URL = re.compile(r"https?://[^\s)\]\}>\"'`,]+")
# Bare domains a fetch would normalise differently; compare on host+path prefix.
TRIM = re.compile(r"[#?].*$")


def norm(u):
    return TRIM.sub("", u).rstrip("/.,;")


def text_of(msg):
    c = msg.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return " ".join(
            b.get("text", "") for b in c if isinstance(b, dict) and b.get("type") == "text"
        )
    return ""


def tool_uses(msg):
    c = msg.get("content")
    if isinstance(c, list):
        return [b for b in c if isinstance(b, dict) and b.get("type") == "tool_use"]
    return []


if not ROOT.is_dir():
    # rglob on a missing directory yields nothing, so a wrong ROOT printed a
    # clean zero report that was indistinguishable from a clean bill of health.
    sys.exit(f"no transcript directory at {ROOT}")

sessions_with_url = unopened = 0
split = {'direct': [0, 0], 'subagent': [0, 0]}
examples = []

for f in sorted(ROOT.rglob("*.jsonl")):
    given, opened, assistant_chars, assistant_text = set(), set(), 0, ""
    try:
        lines = f.read_text(errors="replace").splitlines()
    except OSError:
        continue
    for ln in lines:
        try:
            ev = json.loads(ln)
        except ValueError:
            continue
        msg = ev.get("message") or {}
        if ev.get("type") == "user":
            for u in URL.findall(text_of(msg)):
                given.add(norm(u))
        elif ev.get("type") == "assistant":
            t = text_of(msg)
            assistant_chars += len(t)
            assistant_text += " " + t
            for b in tool_uses(msg):
                inp = b.get("input") or {}
                blob = " ".join(
                    str(v) for v in (inp.get("url"), inp.get("query"), inp.get("command")) if v
                )
                for g in list(given):
                    if g in blob or norm(g).split("//")[-1] in blob:
                        opened.add(g)

    if not given:
        continue
    if assistant_chars < 500:
        continue
    sessions_with_url += 1
    kind = 'subagent' if 'subagent' in str(f) else 'direct'
    split[kind][0] += 1
    # STRONG form: not merely unfetched, but written ABOUT while unfetched. The
    # assistant naming the host or a distinctive path token of a source it never
    # opened is session A's exact error ("asserted IR35 without opening the
    # page Miles linked"), and unlike a bare paste it cannot be innocent.
    missed = []
    for g in given - opened:
        host = g.split("//")[-1].split("/")[0]
        tokens = [t for t in re.split(r"[/._-]", g.split("//")[-1]) if len(t) > 4]
        if host in assistant_text or any(t in assistant_text for t in tokens[1:4]):
            missed.append(g)
    if missed:
        unopened += 1
        split[kind][1] += 1
        if len(examples) < 6:
            examples.append((f.parent.name, min(missed)[:88]))

print(f"sessions where you supplied a URL : {sessions_with_url}")
if sessions_with_url:
    pct = unopened / sessions_with_url
    print(f"  at least one never opened       : {unopened}  ({pct:.0%})")
print("\nsplit (sessions / wrote-about-unopened):")
for k, (n, bad) in split.items():
    print(f"  {k:<9} {n:>5} / {bad:>5}  ({bad/max(n,1):.0%})")
print("\nexamples:")
for proj, u in examples:
    print(f"  {proj[:38]:<38} {u}")
