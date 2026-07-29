#!/usr/bin/env python3
"""Replay search-tool-guard.sh against real historical commands.

Usage:
    # regenerate the corpus (every Bash command ever run, one per line)
    fd -e jsonl . ~/.claude/projects -X cat 2>/dev/null | jq -r \
      'select(.message.content!=null) | .message.content
       | if type=="array" then .[] else empty end
       | select(type=="object" and .name=="Bash") | .input.command // empty' > /tmp/cmds.txt

    .claude/hooks/guard-replay.py /tmp/cmds.txt 600

Note `fd`, not `find`: Claude Code shadows find with bfs, which skips ignored
files, so a find-based sweep silently undercounts.


A guard's test suite proves it does what you meant. This proves what it would
have done to work you actually ran: every in-place-edit command in the history
should warn, and a sample of everything else should be untouched by the new
rule. Fire rate on the sample is the false-positive estimate.
"""

import json
import pathlib
import random
import re
import subprocess
import sys

# Beside this file, not under $HOME: a fresh checkout that is not yet symlinked
# into ~/.claude would otherwise replay some other installed version of the hook,
# or none, rather than the one in the diff being reviewed.
HOOK = pathlib.Path(__file__).resolve().parent / "search-tool-guard.sh"
if not HOOK.exists():
    HOOK = pathlib.Path.home() / ".claude/hooks/search-tool-guard.sh"

if len(sys.argv) < 2:
    sys.exit(__doc__)
CORPUS = pathlib.Path(sys.argv[1])
if not CORPUS.is_file():
    sys.exit(f"no corpus at {CORPUS}; see the extraction command in --help/docstring")
SAMPLE = int(sys.argv[2]) if len(sys.argv) > 2 else 600

INPLACE = re.compile(r"(^|\s)(sed|perl|ruby)\s")
# Deliberately BROADER than the hook: any single-dash cluster holding an `i`,
# minus clusters where a value-taking flag precedes it (`-Ilib`, `-MList`). A
# narrow classifier flatters the guard -- the previous one could not cross the
# digit in `perl -0pi`, so it scored a real catch as a false positive.
CLUSTER = re.compile(r"(?:^|\s)(-[a-zA-Z0-9.]*i[a-zA-Z0-9.]*)")
VALUE_FLAG = re.compile(r"[eEIMmFrCKSx]")


def IFLAG_search(seg):
    if re.search(r"(^|\s)--in-?place([\s=]|$)", seg):
        return True
    return any(
        not VALUE_FLAG.search(cl.split("i")[0]) for cl in CLUSTER.findall(seg)
    )


IFLAG = type("_", (), {"search": staticmethod(IFLAG_search)})()
NEW_RULE = "rewrite in place"


def verdict(cmd):
    """Return (decision, is_new_rule) for one command."""
    try:
        out = subprocess.run(
            [str(HOOK)],
            input=json.dumps({"session_id": "replay", "tool_input": {"command": cmd}}),
            capture_output=True,
            text=True,
            check=False,
            timeout=10,
        ).stdout.strip()
    except subprocess.TimeoutExpired:
        return "TIMEOUT", False
    if not out:
        return "allow", False
    try:
        h = json.loads(out)["hookSpecificOutput"]
    except (ValueError, KeyError):
        return "BADJSON", False
    if h.get("permissionDecision") == "deny":
        return "deny", False
    ctx = h.get("additionalContext", "")
    return ("WARN" if ctx else "allow"), NEW_RULE in ctx


def is_target(cmd):
    """True only if one COMMAND has both the tool and the -i flag.

    Testing the whole line paired ` sed ` with the `-i` belonging to a `grep -i`
    elsewhere in the pipeline, which counted read-only `sed -n` calls as
    in-place edits and reported the guard as missing half its targets. Split on
    command separators the way the hook does.
    """
    return any(
        INPLACE.search(seg) and IFLAG.search(seg)
        for seg in re.split(r"&&|\|\||[;|]", cmd)
    )


cmds = [c for c in CORPUS.read_text(errors="replace").splitlines() if c.strip()]
targets = [c for c in cmds if is_target(c)]
others = [c for c in cmds if c not in set(targets)]

random.seed(20260729)  # fixed: a replay you cannot reproduce is not evidence
others = random.sample(others, min(SAMPLE, len(others)))

missed = [c for c in targets if not verdict(c)[1]]
hit = len(targets) - len(missed)
print(f"in-place commands in history : {len(targets)}")
print(f"  caught by the new rule     : {hit}  ({hit / max(len(targets), 1):.0%})")
print(f"  missed                     : {len(missed)}")
for c in missed[:25]:
    print(f"    | {c[:110]}")

fp = [c for c in others if verdict(c)[1]]
print(f"\nrandom sample of other cmds  : {len(others)}")
print(f"  tripped by the new rule    : {len(fp)}  <- false positives")
for c in fp[:5]:
    print(f"    {c[:100]}")
