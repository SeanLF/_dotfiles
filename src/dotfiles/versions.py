"""Installed-version snapshots, and exactly what changed between two of them."""

import re
import shutil
import subprocess

LISTS = {
    "mise": ["mise", "ls"],
    "uv-tools": ["uv", "tool", "list"],
    "rustup": ["rustup", "toolchain", "list"],
    "brew": ["brew", "list", "--versions"],
    "mas": ["mas", "list"],
}
DIFFED = ("mise", "brew", "uv-tools", "mas")


def record(directory):
    directory.mkdir(parents=True, exist_ok=True)
    for name, cmd in LISTS.items():
        if shutil.which(cmd[0]):
            out = subprocess.run(
                cmd, capture_output=True, text=True, check=False
            ).stdout
            (directory / f"{name}.txt").write_text(out)


def parse(name, text):
    """{package: "v1,v2"} from one tool's version listing."""
    versions = {}
    for line in text.splitlines():
        if line.startswith("-") or len(line.split()) < 2:
            continue
        if name == "mas":
            m = re.match(r"\s*\d+\s+(.*?)\s+\(([^)]*)\)\s*$", line)
            if not m:
                continue
            key, version = m.groups()
        else:
            key, version = line.split()[:2]
        versions.setdefault(key, []).append(version)
    return {k: ",".join(v) for k, v in versions.items()}


def diff(before, after):
    """One line per change, short enough to paste into an agent."""
    lines = []
    for name in DIFFED:
        b, a = before / f"{name}.txt", after / f"{name}.txt"
        if not (b.exists() and a.exists()):
            continue
        old, new = parse(name, b.read_text()), parse(name, a.read_text())
        for key in sorted(old.keys() | new.keys()):
            if key not in old:
                lines.append(f"{name}: {key} added {new[key]}")
            elif key not in new:
                lines.append(f"{name}: {key} removed")
            elif old[key] != new[key]:
                lines.append(f"{name}: {key} {old[key]} -> {new[key]}")
    return lines


def is_major(line):
    """A change of first version number, where behaviour tends to change."""
    if " -> " not in line:
        return False
    old, new = line.rsplit(" -> ", 1)
    first = [re.match(r"\D*(\d*)", v.split()[-1].split(",")[-1])[1] for v in (old, new)]
    return first[0] != first[1]
