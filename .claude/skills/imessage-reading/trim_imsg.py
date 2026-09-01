#!/usr/bin/env python3
"""Compact an imessage-exporter txt export for LLM reading.

Drops: duplicated reply blocks, read receipts, attachment paths, link-preview
blurbs. Compresses: timestamps, sender names, tapbacks.

Given several exports of the same person (Apple splits a conversation across
handles - a phone number and an email address - and the threads overlap in
time), they are merged into one strictly chronological transcript.
"""
import argparse
import re
from pathlib import Path

MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
          "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
MONTH_NUM = {m: i + 1 for i, m in enumerate(MONTHS)}

TS = re.compile(
    r"^(?P<indent> *)"
    r"(?P<mon>Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) "
    r"(?P<day>\d{1,2}), (?P<year>\d{4}) +"
    r"(?P<h>\d{1,2}):(?P<m>\d{2}):(?P<s>\d{2}) (?P<ampm>[AP]M)"
    r"(?P<rest>.*)$"
)
TAPBACK = re.compile(
    r"^(?P<kind>Loved|Liked|Laughed|Emphasized|Questioned|Disliked|.{1,4}) by "
    r"(?P<who>Me|.+)$"
)
EDITED = re.compile(r"^Edited .+? later: (?P<text>.*)$")
ATTACH = re.compile(r"^/Users/\S*/(?:Attachments|StickerCache)/.+$")
DUP_MARK = "This message responded to an earlier message."
PREVIEW_NOISE = re.compile(r"^https?://\S+$")

REACT = {
    "Loved": "♥", "Liked": "+1", "Laughed": "haha",
    "Emphasized": "!!", "Questioned": "?", "Disliked": "-1",
}
KIND_EXT = {
    ".heic": "img", ".png": "img", ".jpg": "img", ".jpeg": "img",
    ".gif": "gif", ".caf": "audio", ".m4a": "audio", ".mp3": "audio",
    ".mov": "video", ".mp4": "video", ".pdf": "pdf",
}


class Msg:
    __slots__ = ("body", "dt", "dup", "indent", "sender", "src", "taps")

    def __init__(self, dt, sender, indent, src=0):
        self.dt, self.sender, self.indent, self.src = dt, sender, indent, src
        self.body, self.taps, self.dup = [], [], False


def parse(path, src=0):
    lines = Path(path).read_text(encoding="utf-8").splitlines()
    msgs, cur, root, want_sender, in_taps = [], None, None, False, False
    i = 0
    while i < len(lines):
        line = lines[i]
        m = TS.match(line)
        # A real message header has nothing after the timestamp but an
        # optional "(Read by ...)". Anything else is an edited-message body.
        if m and (not m["rest"].strip() or m["rest"].lstrip().startswith("(")):
            indent = len(m["indent"])
            dt = (int(m["year"]), MONTH_NUM[m["mon"]], int(m["day"]),
                  int(m["h"]) % 12 + (12 if m["ampm"] == "PM" else 0),
                  int(m["m"]), int(m["s"]))
            cur = Msg(dt, None, indent, src)
            if indent == 0:
                root = cur
            msgs.append(cur)
            want_sender, in_taps = True, False
            i += 1
            continue
        if cur is None:
            i += 1
            continue
        stripped = line.strip()
        if want_sender:
            cur.sender = stripped
            want_sender = False
            i += 1
            continue
        if not stripped:
            i += 1
            continue
        if stripped == "Tapbacks:":
            in_taps = True
            i += 1
            continue
        if stripped == DUP_MARK:
            cur.dup = True
            i += 1
            continue
        if in_taps:
            t = TAPBACK.match(stripped)
            if t:
                cur.taps.append((t["kind"], t["who"]))
                i += 1
                continue
            in_taps = False
        # A zero-indent body line under an indented message belongs to the
        # enclosing root message (the exporter splits parent bodies around
        # their inline reply threads).
        target = root if (cur.indent > 0 and not line.startswith(" ")) else cur
        if target is not None:
            target.body.append(stripped)
        i += 1
    return msgs


def render_body(msg):
    out = []
    for ln in msg.body:
        e = EDITED.match(ln)
        if e:
            if out:
                out[-1] = e["text"]
            else:
                out.append(e["text"])
            continue
        if ATTACH.match(ln):
            name = ln.rsplit("/", 1)[-1]
            ext = "." + name.rsplit(".", 1)[-1].lower() if "." in name else ""
            out.append(f"[{KIND_EXT.get(ext, 'file')}: {name}]")
            continue
        # Strip the timestamp the exporter prepends to edited-message bodies.
        m = TS.match(ln)
        if m and m["rest"].strip():
            ln = m["rest"].strip()
        out.append(ln)
    # Link previews: keep the URL and its title, drop the boilerplate blurb.
    if out and PREVIEW_NOISE.match(out[0]) and len(out) > 2:
        out = out[:2]
    return out


def initials(senders):
    """Map sender names to short labels: Me -> S, others -> first initial."""
    labels, used = {}, {"S"}
    for name in senders:
        if name == "Me":
            labels[name] = "S"
            continue
        stem = name.split()[0] if name.split() else name
        for n in range(1, len(stem) + 1):
            cand = stem[:n].capitalize()
            if cand not in used:
                break
        else:
            cand = stem
        used.add(cand)
        labels[name] = cand
    return labels


def main(sources, dst):
    per_file = [parse(s, i) for i, s in enumerate(sources)]
    msgs = [m for group in per_file for m in group]
    merged = len(sources) > 1
    if merged:
        # Apple splits one conversation across handles and the threads overlap
        # in time, so only a global chronological sort reads as one thread.
        # Sorting also puts each reply at its true position, which makes the
        # per-reply date stamp below unnecessary.
        msgs.sort(key=lambda m: m.dt)
    dups = sum(1 for m in msgs if m.dup)
    kept = [m for m in msgs if not m.dup and (m.body or m.taps)]
    empties = len(msgs) - dups - len(kept)

    # A repeat must come from a different export file: timestamps are
    # second-granular, so two real "ok"s in one thread look identical.
    if merged:
        seen, unique = {}, []
        for m in kept:
            key = (m.dt, m.sender, tuple(m.body))
            if key in seen and m.src not in seen[key]:
                seen[key].add(m.src)
                continue
            seen.setdefault(key, set()).add(m.src)
            unique.append(m)
        cross = len(kept) - len(unique)
        kept = unique
    else:
        cross = 0

    labels = initials(sorted({m.sender for m in kept if m.sender}))
    lines, last_day = [], None
    for m in kept:
        y, mon, d, hh, mm, _ = m.dt
        day = f"{MONTHS[mon - 1]} {d}"
        # A threaded reply can land days after its parent. When merged we are
        # already in true time order so every message may advance the header;
        # unmerged, only top-level messages may, or the transcript looks like
        # it jumps back and forth in time.
        stamp = ""
        if merged or m.indent == 0:
            if day != last_day:
                lines.append(f"\n## {day}, {y}")
                last_day = day
        elif day != last_day:
            stamp = f"({day}) "
        who = labels.get(m.sender, "?")
        arrow = "> " + stamp if m.indent else ""
        body = render_body(m)
        taps = ""
        if m.taps:
            taps = " " + "".join(
                f"[{REACT.get(k, k)}{labels.get(w, w[:1])}]" for k, w in m.taps
            )
        head = f"{hh:02d}:{mm:02d} {who}: {arrow}"
        if not body:
            lines.append(head.rstrip() + taps)
            continue
        lines.append(head + body[0] + (taps if len(body) == 1 else ""))
        for extra in body[1:-1]:
            lines.append(f"        {extra}")
        if len(body) > 1:
            lines.append(f"        {body[-1]}{taps}")
    Path(dst).write_text("\n".join(lines).strip() + "\n", encoding="utf-8")
    note = f", {cross} cross-handle repeats" if cross else ""
    print(f"messages: {len(msgs)} parsed, {dups} duplicate-reply blocks, "
          f"{empties} empty{note}, {len(kept)} kept")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("inputs", nargs="+", help="imessage-exporter .txt export(s)")
    ap.add_argument("-o", "--out", required=True, help="output .md path")
    args = ap.parse_args()
    main(args.inputs, args.out)
