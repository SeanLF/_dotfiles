"""Run a job unattended in its own Rex session; show it only if it needs the user.

  rex-job [--daily-when-idle] NAME -- COMMAND...

Run from a Rex pane, it runs COMMAND right there; otherwise (launchd) it
opens a Rex session NAME-<time> for it and returns. Either way the pane
reports its state in Rex's tab and session picker, shows when a pane waits on
Touch ID, and ends according to COMMAND's exit code:

  0   clean: a session of its own closes itself
  1   failed or warned: error, stays open
  2   worth a look: done with a message, stays until the next run
  3   needs action: blocked; Enter starts Claude with the job's prompt
  75  couldn't run (e.g. offline): closes, and counts as not having run

COMMAND may write {"message", "report", "prompt"} as JSON to $REX_JOB_OUT.
--daily-when-idle starts it once a day, after 15 idle minutes (or regardless
after 2 days), and only online: what launchd calls hourly.
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile
from datetime import date, datetime
from pathlib import Path

from . import STATE, online, rex, schedule, use_tool_path

CLEAN, FAILED, LOOK, ACTION, TEMPFAIL = 0, 1, 2, 3, 75
PROMPTS = ("sudo", "op")


def outcome(code, out):
    """(Rex state, message, kind) for how the job ended; state None closes the session."""
    message = out.get("message", "")
    if code == CLEAN or code == TEMPFAIL:
        return None, "", ""
    if code == LOOK:
        return "done", message, ""
    if code == ACTION:
        return "blocked", message, "permission"
    return "error", message or f"exit {code}", ""


# Previous runs that finished done are closed; one still working means this one
# doesn't start. A session waiting on the user (an alert) never holds up the next
# run, or one ignored alert would stop every upgrade after it.
def clear_previous(name):
    for session in rex.sessions(f"{name}-"):
        state = rex.session_state(session["session_id"])
        if state == "done":
            rex.kill(session["session_id"])
        elif state == "working":
            return False
    return True


def start(name, command, daily_when_idle):
    if daily_when_idle:
        last = schedule.last_run(STATE / "rex-job" / name / "last-run")
        if not schedule.due(last, date.today(), schedule.idle_seconds) or not online():
            return 0
    if not clear_previous(name):
        return 0
    inside = [
        sys.argv[0],
        "--inside",
        *(["--daily-when-idle"] if daily_when_idle else []),
        name,
        "--",
        *command,
    ]
    rex.new_session(f"{name}-{datetime.now():%Y-%m-%d-%H%M}", Path.cwd(), inside)
    return 0


def watch(proc, session, ignore=frozenset()):
    """Wait for the job, marking it blocked while one of its panes waits on Touch ID.
    `ignore` holds panes that were already open, so the user's own don't count."""
    seen = blocked = None
    while True:
        try:
            return proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            pass
        who = next(
            (p for p in PROMPTS if p in rex.running_under(session, ignore)), None
        )
        # Two polls in a row, so a sudo with cached credentials doesn't flicker the tab.
        if who and who == seen and not blocked:
            rex.status("blocked", f"waiting on Touch ID for {who}", "auth")
            blocked = who
        elif not who and blocked:
            rex.status("working")
            blocked = None
        seen = who


def inside(name, command, daily, inline=False):
    session = os.environ["REX_SESSION"]
    others = set(rex.blocks(session)) - {os.environ["REX_BLOCK"]} if inline else set()
    out_file = Path(tempfile.mkstemp(prefix=f"{name}.", suffix=".json")[1])
    rex.status("working")
    env = {**os.environ, "REX_JOB_OUT": str(out_file)}
    if daily:
        # Nobody is at the keyboard: steps must not start what waits on a person.
        env["REX_JOB_UNATTENDED"] = "1"
    proc = subprocess.Popen(command, env=env)
    code = watch(proc, session, frozenset(others))
    out = json.loads(out_file.read_text() or "{}")
    out_file.unlink()

    # Only the daily gate reads this, so only its runs count, and only if they ran.
    if daily and code != TEMPFAIL:
        last = STATE / "rex-job" / name / "last-run"
        last.parent.mkdir(parents=True, exist_ok=True)
        last.write_text(str(date.today()))
    state, message, kind = outcome(code, out)
    if state is None:
        if inline:
            rex.status("done", "offline" if code == TEMPFAIL else "")
        else:
            rex.kill(session)
        return code
    rex.status(state, message, kind)
    if state == "blocked" and out.get("prompt"):
        try:
            input("\nEnter starts Claude on this; Ctrl-C closes. ")
        except KeyboardInterrupt, EOFError:
            return code
        os.execvp("claude", ["claude", out["prompt"]])
    return code


def main():
    use_tool_path()
    parser = argparse.ArgumentParser(
        prog="rex-job",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--daily-when-idle",
        action="store_true",
        help="once a day, while the user is away",
    )
    parser.add_argument("--inside", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("name")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("no COMMAND after --")
    if args.inside:
        return inside(args.name, command, args.daily_when_idle)
    # Typed in a Rex pane: run here, where the user already is.
    if rex.available() and sys.stdin.isatty() and not args.daily_when_idle:
        return inside(args.name, command, daily=False, inline=True)
    return start(args.name, command, args.daily_when_idle)


if __name__ == "__main__":
    sys.exit(main())
