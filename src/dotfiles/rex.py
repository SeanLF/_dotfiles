"""Talking to Rex: a terminal's status (OSC 7501), sessions and panes."""

import base64
import json
import os
import shutil
import sys

from . import attempt, run


def available():
    return (
        bool(os.environ.get("REX_BLOCK"))
        and sys.stdout.isatty()
        and shutil.which("rex") is not None
    )


def status(state, msg="", kind="", app="rex-job"):
    """Show this terminal's state in Rex's tab and session picker."""
    if not available():
        return
    pairs = f"state={state}:app={app}"
    if msg:
        pairs += ":msg=" + base64.b64encode(msg.encode()).decode()
    if kind:
        pairs += f":kind={kind}"
    sys.stdout.write(f"\033]7501;{pairs}\a")
    sys.stdout.flush()


def call(*args):
    return json.loads(run("rex", *args))


def sessions(prefix):
    return [
        s for s in call("ls", "--json")["sessions"] if s["label"].startswith(prefix)
    ]


def blocks(session):
    data = call("block", "ls", "-s", session, "--json")
    found = []

    def walk(node):
        if isinstance(node, str) and node.startswith("block:") and node not in found:
            found.append(node)
        elif isinstance(node, dict):
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    walk(data)
    return found


def session_state(session):
    """The state the session's first pane last reported, if any."""
    first = next(iter(blocks(session)), None)
    if not first:
        return None
    records = call("block", "call", "-s", session, "-b", first, "program_status", "{}")[
        "records"
    ]
    return records[0]["state"] if records else None


def descendants(table, root):
    """Names of every process under `root`, from (pid, ppid, name) rows."""
    children = {}
    for pid, ppid, name in table:
        children.setdefault(ppid, []).append((pid, name))
    names, todo = set(), [root]
    while todo:
        for pid, name in children.get(todo.pop(), []):
            names.add(name)
            todo.append(pid)
    return names


def process_table():
    rows = []
    for line in attempt("ps", "-axo", "pid=,ppid=,comm=").stdout.splitlines():
        pid, ppid, comm = line.split(None, 2)
        rows.append((int(pid), int(ppid), comm.rsplit("/", 1)[-1]))
    return rows


def running_under(session, ignore=frozenset()):
    """Every program running in the session's panes, however deep: a step under
    script(1) sits on a private terminal, so a pane's foreground alone hides it."""
    table, names = process_table(), set()
    for block in blocks(session):
        if block in ignore:
            continue
        proc = attempt(
            "rex", "block", "call", "-s", session, "-b", block, "process", "{}"
        )
        if proc.returncode == 0:
            child = (json.loads(proc.stdout).get("child") or {}).get("pid")
            if child:
                names |= descendants(table, child)
    return names


def new_session(label, cwd, command):
    run("rex", "new", label, "--keep-open", "-c", str(cwd), "--", *command)


def kill(session):
    attempt("rex", "kill", session)


def split(anchor, direction, cwd, command):
    out = run(
        "rex",
        "split",
        "-b",
        anchor,
        "--split",
        direction,
        "--focus=false",
        "--keep-open",
        "--json",
        "-c",
        str(cwd),
        "--",
        *command,
    )
    return json.loads(out)["block_ids"][0]


def wait(block):
    return attempt("rex", "wait", block).returncode


def close_block(session, block):
    attempt("rex", "block", "close", "-s", session, block)
