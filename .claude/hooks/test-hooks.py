import json
import pathlib
import subprocess

H = pathlib.Path.home() / ".claude/hooks"
S = H / "search-tool-guard.sh"


def run(hook, cmd, sid="tst"):
    payload = json.dumps({"session_id": sid, "tool_input": {"command": cmd}})
    out = subprocess.run(
        [str(hook)], input=payload, capture_output=True, text=True, check=False
    ).stdout.strip()
    if not out:
        return "allow"
    try:
        h = json.loads(out)["hookSpecificOutput"]
    except (ValueError, KeyError):
        return "BADJSON"
    if h.get("permissionDecision") == "deny":
        return "deny"
    return "WARN" if h.get("additionalContext") else "allow"


CASES = [
    (S, "echo \"don't worry\" && rg -rn 'foo' bar", "deny", "apostrophe no longer blinds guard"),
    (S, "rg -tr -n pattern", "allow", "rg --type r is valid"),
    (S, "rg -n foo $(fd -tr .)", "allow", "fd cluster in substitution"),
    (S, "rg -rn foo", "deny", "real replace bundle"),
    (S, "find . -name x; rg -rn foo", "deny", "warn must not preempt deny"),
    (S, "grep -n foo f.txt", "WARN", "shadowed grep warns"),
    (S, "rtk init -g --codex", "deny", "rtk clobber guarded"),
    (S, "rtk init -g --gemini", "deny", "rtk clobber guarded"),
    (S, "rtk init", "allow", "project-local rtk init fine"),
    (S, "rtk gain", "allow", "other rtk subcommands fine"),
    (S, 'cat <<EOF\nnever run rg -rn foo\nEOF', "allow", "heredoc mention not denied"),
    # WARN not deny: bulk/multi-file rewrites are a real use Edit cannot serve.
    (S, "sed -i '' 's/a/b/' f.txt", "WARN", "in-place sed warns"),
    (S, "perl -pi -e 's/a/b/' f.txt", "WARN", "in-place perl warns"),
    (S, "ruby -i -pe 'gsub(/a/,\"b\")' f.txt", "WARN", "in-place ruby warns"),
    # `-i` need not end the cluster: GNU sed reads `-in` as -i with suffix "n".
    (S, "sed -in 's/a/b/' f.txt", "WARN", "-i not last in cluster"),
    (S, "sed -iE 's/a/b/' f.txt", "WARN", "-i before another toggle"),
    (S, "perl -0pi -e 's/a/b/' f.txt", "WARN", "digit in the flag cluster"),
    (S, "perl -Ilib -pi -e 's/a/b/' f.txt", "WARN", "real -pi after a value flag"),
    (S, "sed -ri 's/a/b/' f.txt", "WARN", "sed -ri: r is a sed toggle"),
    (S, "ruby -rnokogiri -e 'puts 1'", "allow", "ruby -r takes a value"),
    (S, "gsed -i '' 's/a/b/' f.txt", "WARN", "gsed reached"),
    (S, "/usr/bin/sed -i '' 's/a/b/' f.txt", "WARN", "absolute path reached"),
    (S, "perl -MList::Util -e 'print 1'", "allow", "the i in -MList is a value"),
    (S, "sed -n '1,5p' f.txt", "allow", "sed -n untouched"),
    (S, "sed 's/#.*//' f.txt", "allow", "read-only sed untouched"),
    (S, "perl -e 'print time'", "allow", "perl without -i untouched"),
    (S, "ruby -Ilib -e 'puts 1'", "allow", "-Ilib is not -i"),
    (S, "python3 -c 'print(s.replace(1,2))'", "allow", "read-only python replace untouched"),
    (S, "rg -rn foo && sed -i '' 's/a/b/' f", "deny", "deny still beats the new warn"),
]

fails = 0
for hook, cmd, want, label in CASES:
    got = run(hook, cmd)
    ok = got == want
    fails += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {label:<44} {got:<6} (want {want})")

print()
print("=== warn tier: two rules in one command must both survive ===")


def ctx(cmd):
    out = subprocess.run(
        [str(S)],
        input=json.dumps({"session_id": "tst", "tool_input": {"command": cmd}}),
        capture_output=True,
        text=True,
        check=False,
    ).stdout.strip()
    try:
        return json.loads(out)["hookSpecificOutput"].get("additionalContext", "")
    except (ValueError, KeyError):
        return ""


# A single-slot warn() would let the later rule silently replace the earlier one.
for cmd, label in [
    ("sed -i '' 's/a/b/' f && grep -n x f", "in-place warn survives a later grep warn"),
    ("grep -n x f && sed -i '' 's/a/b/' f", "grep warn survives a later in-place warn"),
]:
    c = ctx(cmd)
    both = "rewrite in place" in c and "shadowed by Claude Code" in c
    fails += not both
    print(f"{'ok  ' if both else 'FAIL'} {label}")

print()
print("=== steer.sh: Stop with a subagent running is not 'done' ===")
import os
import tempfile

STEER = pathlib.Path(__file__).parent / "steer.sh"


def steer_state(event, running, kind="subagent"):
    with tempfile.TemporaryDirectory() as d:
        shims = pathlib.Path(d, "bin")
        shims.mkdir()
        # Nothing may reach the real Steer.
        for tool in ("pgrep", "open", "osascript", "logger"):
            (shims / tool).write_text("#!/bin/sh\nexit 1\n")
            (shims / tool).chmod(0o755)
        tasks = [{"id": "t", "type": kind, "status": "running"}] if running else []
        env = dict(os.environ, PATH=f"{shims}:{os.environ['PATH']}", STEER_STATE_DIR=d + "/state")
        subprocess.run(
            [str(STEER), event],
            input=json.dumps({"session_id": "tst", "cwd": d, "background_tasks": tasks}),
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        f = pathlib.Path(d, "state", "tst")
        return f.read_text().split("\t")[0] if f.exists() else "none"


# A background shell such as a dev server may never exit, so it never wakes Claude.
for event, running, kind, want in [
    ("done", False, "subagent", "done"),
    ("done", True, "subagent", "working"),
    ("idle", True, "subagent", "idle"),
    ("approval", True, "subagent", "approval"),
    ("done", True, "shell", "done"),
    ("idle", True, "shell", "idle"),
]:
    got = steer_state(event, running, kind)
    fails += got != want
    print(f"{'ok  ' if got == want else 'FAIL'} {event} with running {kind if running else 'nothing'}: {got} (want {want})")

print()
print("=== steer.sh: sends go to the running Steer's own bundle, never the scheme's handler ===")
import time


def steer_opens(comm):
    """The `open` calls steer.sh makes while `comm` is what ps reports for the running Steer."""
    with tempfile.TemporaryDirectory() as d:
        shims = pathlib.Path(d, "bin")
        shims.mkdir()
        log = pathlib.Path(d, "open.log")
        (shims / "pgrep").write_text("#!/bin/sh\necho 4242\n")
        # Only the pid lookup is faked; the session walk's `ps -eo` falls through to the real ps.
        (shims / "ps").write_text(
            f"#!/bin/sh\ncase \"$*\" in *'-p 4242'*) printf '%s\\n' {json.dumps(comm)} ;; *) exec /bin/ps \"$@\" ;; esac\n"
        )
        (shims / "open").write_text(f"#!/bin/sh\nprintf '%s|' \"$@\" >>{log}\necho >>{log}\n")
        for tool in ("pgrep", "ps", "open"):
            (shims / tool).chmod(0o755)
        env = dict(os.environ, PATH=f"{shims}:{os.environ['PATH']}", STEER_STATE_DIR=d + "/state")
        subprocess.run(
            [str(STEER), "done"],
            input=json.dumps({"session_id": "tst", "cwd": d}),
            env=env, capture_output=True, text=True, check=False,
        )
        # The sends run detached; three lines (player-lights, mute-light, haptic) or a settled silence.
        for _ in range(30):
            if log.exists() and len(log.read_text().splitlines()) >= 3:
                break
            time.sleep(0.1)
        return log.read_text().splitlines() if log.exists() else []


for label, comm, bundle in [
    ("installed", "/Applications/Steer.app/Contents/MacOS/Steer", "/Applications/Steer.app"),
    ("Dev", f"{pathlib.Path.home()}/Developer/steer/Steer Dev.app/Contents/MacOS/Steer", f"{pathlib.Path.home()}/Developer/steer/Steer Dev.app"),
    # The case that launched the installed app beside a benchmark: a release build from the repo.
    ("release build", f"{pathlib.Path.home()}/Developer/steer/Steer.app/Contents/MacOS/Steer", f"{pathlib.Path.home()}/Developer/steer/Steer.app"),
    # Quitting between pgrep and the send: ps reads empty, so nothing may be sent.
    ("exiting", "", None),
    ("not a bundle", "/usr/local/bin/Steer", None),
    # Any process can call itself Steer; only the installed app and the checkout's builds are opened.
    ("foreign bundle", "/tmp/evil.app/Contents/MacOS/Steer", None),
]:
    calls = steer_opens(comm)
    # Steer ignores an unknown route, so a misspelt one fails silently on the controller.
    routes = sorted(c.split("|steer://", 1)[-1].split("/", 1)[0] for c in calls)
    want_ok = (
        all(c.startswith(f"-g|-a|{bundle}|steer://") for c in calls) and routes == ["haptic", "mute-light", "player-lights"]
        if bundle
        else calls == []
    )
    fails += not want_ok
    print(f"{'ok  ' if want_ok else 'FAIL'} {label}: {calls}")

print()
print("FAILURES:", fails)
