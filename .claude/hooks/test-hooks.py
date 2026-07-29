import json
import pathlib
import subprocess

H = pathlib.Path.home() / ".claude/hooks"
S, C, P = H / "search-tool-guard.sh", H / "commit-guard.sh", H / "pre-commit-review.sh"

FORCE = "/tmp/claude-commit-force-tst"
pathlib.Path(FORCE).unlink(missing_ok=True)


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
    # (hook, command, expected, label)
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
    (C, "echo \"don't\" && git commit -m 'bad message'", "deny", "apostrophe no longer blinds commit guard"),
    (C, "git -C /tmp commit -m 'nope'", "deny", "git -C bypass closed"),
    (C, "git -c user.name=x commit -m 'nope'", "deny", "git -c bypass closed"),
    (C, 'git commit -m "feat(x): why" -m "body prose"', "allow", "subject+body allowed"),
    (C, 'git commit -am "fix(y): why"', "allow", "-am good"),
    (C, 'git commit -am "nope"', "deny", "-am bad still caught"),
    (C, 'git commit -m "fixup! feat(x): y"', "allow", "autosquash allowed"),
    (C, 'git commit -m "updated the thing"', "deny", "non-conventional denied"),
    (C, 'git commit -m "feat(x): sparkle ✨"', "deny", "emoji denied"),
    (P, "git log --grep commit -5", "allow", "read-only git log must not trip gate"),
    (P, "echo 'later: git commit -m x'", "allow", "quoted mention must not trip gate"),
    (P, "git commit -m 'feat(x): y'", "deny", "real commit still gated"),
]

fails = 0
for hook, cmd, want, label in CASES:
    got = run(hook, cmd)
    ok = got == want
    fails += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {label:<44} {got:<6} (want {want})")

print()
print("=== shared sentinel: one touch must satisfy BOTH gates ===")
pathlib.Path(FORCE).touch()
a = run(C, "git commit --amend -m 'fix: x'")
still = pathlib.Path(FORCE).exists()
print(f"commit-guard with marker -> {a} (want allow); marker survived: {still} (want True)")
fails += a != "allow" or not still
pathlib.Path(FORCE).unlink(missing_ok=True)

print()
print("=== sentinel: every name the deny message gives must clear the gate ===")
SENT = H / "post-review-sentinel.sh"
SENT_MARK = pathlib.Path("/tmp/claude-review-done-senttest")


def fires(agent):
    SENT_MARK.unlink(missing_ok=True)
    subprocess.run(
        [str(SENT)],
        input=json.dumps({"session_id": "senttest", "tool_input": {"subagent_type": agent}}),
        capture_output=True,
        text=True,
        check=False,
    )
    hit = SENT_MARK.exists()
    SENT_MARK.unlink(missing_ok=True)
    return hit


# Must clear: exactly the names pre-commit-review.sh tells you to run.
# Must not: a name that does not exist, and an unrelated agent.
SENTINEL_CASES = [
    ("pr-review-toolkit:code-reviewer", True),
    ("pr-review-toolkit:code-simplifier", True),
    ("pr-review-toolkit:silent-failure-hunter", True),
    ("code-simplifier:code-simplifier", True),
    ("feature-dev:code-reviewer", True),
    ("adversarial-reviewer", True),
    ("superpowers:code-reviewer", False),
    ("general-purpose", False),
]
for agent, want in SENTINEL_CASES:
    got = fires(agent)
    ok = got == want
    fails += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {agent:<44} clears={got} (want {want})")

# The deny message must not name anything that cannot clear the gate.
named = [
    ln.strip()
    for ln in (H / "pre-commit-review.sh").read_text().splitlines()
    if ln.strip().count(":") == 1 and ln.strip().split(":")[0] in
    {"pr-review-toolkit", "code-simplifier", "feature-dev", "superpowers"}
]
for n in named:
    agent = n.split()[0]
    if not fires(agent):
        print(f"FAIL deny message names {agent}, which does not clear the gate")
        fails += 1

print()
print("FAILURES:", fails)
