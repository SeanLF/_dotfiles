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
print("FAILURES:", fails)
