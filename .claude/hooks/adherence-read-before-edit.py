#!/usr/bin/env python3
"""Base rate for one AGENTS.md rule, measured on real history.

The rule: read a repo's own docs before proposing changes to it. Three sessions
failed it, so before rewording anything, measure how often it actually happens.

Per transcript, walk tool calls in order. When the first Edit/Write lands inside
a repo under ~/Developer/, ask whether that repo's own AGENTS.md / CLAUDE.md /
docs/DECISIONS.md was opened FIRST, by either a Read call or a Bash command that
names the path (rg/cat/sed -n all count as reading; only counting Read calls
would have scored this very session as a violation).
"""

import json
import pathlib
import re
import sys

ROOT = (
    pathlib.Path(sys.argv[1])
    if len(sys.argv) > 1
    else pathlib.Path.home() / ".claude/projects"
)
DEV = str(pathlib.Path.home() / "Developer") + "/"
DOCS = ("AGENTS.md", "CLAUDE.md", "DECISIONS.md")

# Only count repos with enough activity to be a real working session.
MIN_EDITS = 2


def repo_of(path):
    if not path or not path.startswith(DEV):
        return None
    rest = path[len(DEV):].split("/")
    return rest[0] if rest and rest[0] else None


def blocks(msg):
    c = msg.get("content")
    if isinstance(c, list):
        return [b for b in c if isinstance(b, dict) and b.get("type") == "tool_use"]
    return []


if not ROOT.is_dir():
    sys.exit(f"no transcript directory at {ROOT}")

# The repo whose docs Claude Code auto-loads is read from each transcript's own
# `cwd`, NOT decoded from the project directory name. Decoding the name only
# undid one rename, so a worktree dir (steer--claude-worktrees-audit) yielded a
# repo that could never equal `repo_of(edit_path)`. The self-repo exclusion then
# never fired and those sessions were counted as unread cross-repo edits,
# inflating the very number this script exists to report.
compliant = violation = 0
offenders = {}
DOC_PATH = re.compile(
    re.escape(DEV) + r"([^/\s\"']+)(?:/[^\s\"']*)?/(?:" + "|".join(DOCS) + r")"
)

for f in ROOT.rglob("*.jsonl"):
    mine = None
    read_docs, first_edit, edits = set(), {}, {}
    try:
        lines = f.read_text(errors="replace").splitlines()
    except OSError:
        continue
    for ln in lines:
        try:
            ev = json.loads(ln)
        except ValueError:
            continue
        if mine is None:
            mine = repo_of(ev.get("cwd") or "")
        for b in blocks(ev.get("message") or {}):
            name, inp = b.get("name"), b.get("input") or {}
            if name in ("Read", "Glob", "Grep"):
                p = inp.get("file_path") or inp.get("path") or ""
                r = repo_of(p)
                if r and any(d in p for d in DOCS):
                    read_docs.add(r)
            elif name == "Bash":
                # Credit only the repo whose doc path actually appears. Testing
                # `any(doc in cmd)` and then adding EVERY Developer/ path in the
                # command marked unrelated repos as read, hiding violations.
                for m in DOC_PATH.finditer(inp.get("command") or ""):
                    read_docs.add(m.group(1))
            elif name in ("Edit", "Write", "NotebookEdit"):
                r = repo_of(inp.get("file_path") or "")
                if not r:
                    continue
                edits[r] = edits.get(r, 0) + 1
                if r not in first_edit:
                    first_edit[r] = r in read_docs

    for r, seen in first_edit.items():
        if edits.get(r, 0) < MIN_EDITS or r == mine:
            continue
        if seen:
            compliant += 1
        else:
            violation += 1
            offenders[r] = offenders.get(r, 0) + 1

total = compliant + violation
print(f"repo-sessions with >={MIN_EDITS} edits : {total}")
if total:
    print(f"  docs read before first edit      : {compliant}  ({compliant/total:.0%})")
    print(f"  edited without reading its docs  : {violation}  ({violation/total:.0%})")
print("\ntop repos edited without reading their docs:")
for r, n in sorted(offenders.items(), key=lambda kv: -kv[1])[:10]:
    print(f"  {n:>4}  {r}")
