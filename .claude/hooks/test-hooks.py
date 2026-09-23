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
    (S, 'cat <<EOF\nnever run rg -rn foo\nEOF', "allow", "heredoc mention not denied"),
    # In-place edit idioms: a no-match rewrites nothing and still exits 0, so a
    # failed edit is indistinguishable from an applied one. 305 real uses across
    # 228k historical commands, so this warns rather than denies.
    (S, "sed -i '' 's/a/b/' f.txt", "WARN", "in-place sed warns"),
    (S, "perl -pi -e 's/a/b/' f.txt", "WARN", "in-place perl warns"),
    (S, "ruby -i -pe 'gsub(/a/,\"b\")' f.txt", "WARN", "in-place ruby warns"),
    # `-i` need not end the cluster: GNU sed reads `-in` as -i with suffix "n".
    (S, "sed -in 's/a/b/' f.txt", "WARN", "-i not last in cluster"),
    (S, "sed -iE 's/a/b/' f.txt", "WARN", "-i before another toggle"),
    (S, "perl -0pi -e 's/a/b/' f.txt", "WARN", "digit in the flag cluster"),
    (S, "perl -Ilib -pi -e 's/a/b/' f.txt", "WARN", "real -pi after a value flag"),
    # -r is a bare toggle for sed but value-taking for ruby, so one shared
    # exclusion table silently dropped `sed -ri`.
    (S, "sed -ri 's/a/b/' f.txt", "WARN", "sed -ri: r is a sed toggle"),
    (S, "ruby -rnokogiri -e 'puts 1'", "allow", "ruby -r takes a value"),
    # gsed is in this repo's Brewfile; a bareword-only match missed it.
    (S, "gsed -i '' 's/a/b/' f.txt", "WARN", "gsed reached"),
    (S, "/usr/bin/sed -i '' 's/a/b/' f.txt", "WARN", "absolute path reached"),
    (S, "perl -MList::Util -e 'print 1'", "allow", "the i in -MList is a value"),
    (S, "sed -n '1,5p' f.txt", "allow", "sed -n untouched"),
    (S, "sed 's/#.*//' f.txt", "allow", "read-only sed untouched"),
    (S, "perl -e 'print time'", "allow", "perl without -i untouched"),
    (S, "ruby -Ilib -e 'puts 1'", "allow", "-Ilib is not -i"),
    # 51 of 54 historical `python -c ... replace` calls never write a file.
    # Guarding the idiom would be 94% false positives, so it is not guarded.
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


# A single-slot warn() meant the later grep rule silently replaced the earlier
# in-place rule, so the command that most needed the warning got the other one.
for cmd, label in [
    ("sed -i '' 's/a/b/' f && grep -n x f", "in-place warn survives a later grep warn"),
    ("grep -n x f && sed -i '' 's/a/b/' f", "grep warn survives a later in-place warn"),
]:
    c = ctx(cmd)
    both = "rewrite in place" in c and "shadowed by Claude Code" in c
    fails += not both
    print(f"{'ok  ' if both else 'FAIL'} {label}")

# The agent-name roster and the review gate's deny message are covered by
# tests/test-review-gate.sh, which has a real git repo to record against.

print()
print("FAILURES:", fails)
