"""Check installed software against advisories not reported before.

grype matches what mise, uv and mise's npm tools installed; CISA's KEV feed
covers apps and brew packages grype can't see. An alert is anything exploited
in the wild, EPSS >= 0.9, or a malicious package. maintenance runs this after
upgrading; `advisory-scan` runs it alone.

  advisory-scan [--dry-run] [--out FILE]
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import date, datetime
from pathlib import Path

from . import HOME, STATE, attempt, run, use_tool_path

STATE = STATE / "advisory-scan"
SEEN = STATE / "seen.json"
MISE = HOME / ".local/share/mise/installs"
UV_TOOLS = HOME / ".local/share/uv/tools"
KEV_URL = "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json"
# EPSS is the modelled chance of exploitation in the next 30 days; 10% is a
# common line for "act now" (the percentile would flag the top 10% of all CVEs).
EPSS_ALERT = 0.1
# Lockfiles that gems ship as test fixtures, and the Go toolchain's source tree.
MISE_EXCLUDES = [
    # Lockfiles that gems ship as test fixtures.
    "./**/Gemfile.lock",
    # Trees grype would walk for nothing: gem sources (installed gems are read
    # from their specifications), Ruby's docs, and the Go toolchain's sources
    # and packages (its binaries carry the version).
    "./ruby/*/lib/ruby/gems/*/gems/**",
    "./ruby/*/share/**",
    "./go/*/src/**",
    "./go/*/pkg/**",
    "./**/go.mod",
]


def grype(root, excludes=()):
    args = ["grype", f"dir:{root}", "-q", "-o", "json"]
    for pattern in excludes:
        args += ["--exclude", pattern]
    # The database is updated once, before the scans start.
    env = {**os.environ, "GRYPE_DB_AUTO_UPDATE": "false"}
    out = subprocess.run(
        args, capture_output=True, text=True, check=True, env=env
    ).stdout
    return json.loads(out)["matches"]


def grype_findings():
    """The three scans run side by side; each is mostly walking files."""
    # Best effort: maintenance fetched it already, and a stale database still scans.
    attempt("grype", "db", "update")
    with tempfile.TemporaryDirectory() as stage:
        # mise's npm backend writes a pnpm-format lockfile under its own name.
        for lock in MISE.glob("npm-*/latest/*-lock.yaml"):
            tool = Path(stage) / lock.parent.parent.name
            tool.mkdir(exist_ok=True)
            shutil.copy(lock, tool / "pnpm-lock.yaml")
        scans = [
            (MISE, MISE_EXCLUDES, lambda p: " ".join(p[:2])),
            (UV_TOOLS, (), lambda p: f"uv tool {p[0]}"),
            (Path(stage), (), lambda p: f"mise {p[0]}"),
        ]
        with ThreadPoolExecutor() as pool:
            results = list(pool.map(lambda s: grype(s[0], s[1]), scans))
    for (_, _, owner_of), matches in zip(scans, results, strict=True):
        yield from from_grype(matches, owner_of)


def from_grype(matches, owner_of):
    for m in matches:
        v, a = m["vulnerability"], m["artifact"]
        owner = owner_of(a["locations"][0]["path"].strip("/").split("/"))
        epss = max((e.get("epss", 0) for e in v.get("epss") or []), default=0)
        malicious = bool(
            re.search(
                r"\bmalware\b|malicious (code|package)",
                v.get("description") or "",
                re.IGNORECASE,
            )
        )
        exploited = bool(v.get("knownExploited"))
        yield {
            "key": f"{v['id']} {a['name']}@{a['version']} {owner}",
            "owner": owner,
            "what": f"{a['name']}@{a['version']}",
            "id": v["id"],
            "severity": v.get("severity", "Unknown"),
            "why": ", ".join(
                w
                for w, on in [
                    ("MALICIOUS", malicious),
                    ("exploited", exploited),
                    (f"EPSS {epss:.2f}", epss >= EPSS_ALERT),
                ]
                if on
            ),
            "fix": ", ".join(v.get("fix", {}).get("versions") or []) or "none yet",
            "alert": malicious or exploited or epss >= EPSS_ALERT,
        }


def words(s):
    return " ".join(re.findall(r"[a-z0-9]+", s.lower()))


# Whole names, not their parts: "github-desktop" must not match every "Desktop".
def installed_names():
    names = {"apple", "chromium"}
    names |= {n.split("@")[0] for n in run("brew", "list", "--formula", "-1").split()}
    names |= set(run("brew", "list", "--cask", "-1").split())
    names |= {p.stem for p in Path("/Applications").glob("*.app")}
    return {w for w in map(words, names) if len(w) >= 4}


def kev_findings():
    names = installed_names()
    with urllib.request.urlopen(KEV_URL, timeout=60) as r:
        feed = json.load(r)
    for v in feed["vulnerabilities"]:
        product = f"{v['vendorProject']} {v['product']}"
        text = f" {words(product)} "
        if any(f" {n} " in text for n in names):
            yield {
                "key": f"kev {v['cveID']}",
                "owner": product,
                # Identifiers only: the feed's prose fields reach Claude via the report.
                "what": product,
                "id": v["cveID"],
                "severity": "KEV",
                "why": "exploited",
                "fix": "see the CISA KEV entry",
                "alert": True,
            }


# Package names and feed text come from strangers, and the report is handed to
# Claude: keep only characters an ID, name@version or short phrase needs.
def clean(text, limit=80):
    return re.sub(r"[^A-Za-z0-9 ._@/:+,()-]", "", str(text))[:limit]


def report(findings, title):
    by_owner = {}
    for f in findings:
        by_owner.setdefault(f["owner"], []).append(f)
    lines = [f"# {title}", ""]
    for owner, fs in sorted(
        by_owner.items(), key=lambda kv: (-sum(f["alert"] for f in kv[1]), -len(kv[1]))
    ):
        lines.append(
            f"## {clean(owner)} ({len(fs)} new, {sum(f['alert'] for f in fs)} alert)"
        )
        for f in sorted(fs, key=lambda f: not f["alert"]):
            flag = f"ALERT ({f['why']}) " if f["alert"] else ""
            lines.append(
                f"- {flag}{clean(f['id'], 40)} {clean(f['what'])}: {clean(f['severity'], 20)};"
                f" fix: {clean(f['fix'])}"
            )
        lines.append("")
    return "\n".join(lines)


def scan(dry_run=False):
    """New findings since the last scan: {"report": path or None, "new": n, "alerts": [line]}."""
    STATE.mkdir(parents=True, exist_ok=True)
    seeding = not SEEN.exists()
    seen = set() if seeding else set(json.loads(SEEN.read_text()))

    found = list(grype_findings()) + list(kev_findings())
    new = [f for f in found if f["key"] not in seen]
    # Historical KEV entries are years old; the baseline only surfaces live exposure.
    if seeding:
        new = [f for f in new if not f["key"].startswith("kev ")]
    text = report(
        new, f"Advisories {date.today()}" + (" (baseline)" if seeding else "")
    )
    alerts = [ln for ln in text.splitlines() if ln.startswith("- ALERT")]

    path = None
    if not dry_run:
        SEEN.write_text(json.dumps(sorted(seen | {f["key"] for f in found})))
        if new:
            path = STATE / f"{datetime.now():%Y-%m-%d-%H%M}.md"
            path.write_text(text)
    return {
        "report": path and str(path),
        "new": len(new),
        "alerts": alerts,
        "text": text,
    }


def main():
    use_tool_path()
    parser = argparse.ArgumentParser(
        prog="advisory-scan",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--dry-run", action="store_true", help="leave the seen-list and reports alone"
    )
    parser.add_argument(
        "--out",
        metavar="FILE",
        help="also write the result as JSON (what maintenance reads)",
    )
    args = parser.parse_args()
    result = scan(dry_run=args.dry_run)
    print(result["text"] if result["new"] else "no new advisories")
    if result["report"]:
        print(f"\nreport: {result['report']}")
    if args.out:
        Path(args.out).write_text(
            json.dumps({k: v for k, v in result.items() if k != "text"})
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
