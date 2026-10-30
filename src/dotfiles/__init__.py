"""Commands behind this Mac's upkeep, installed with `uv tool install --editable`."""

import os
import subprocess
from pathlib import Path

HOME = Path.home()
# An editable install, so this is the checkout itself.
REPO = Path(__file__).resolve().parents[2]
STATE = HOME / ".local/state"


def use_tool_path():
    """launchd and Rex start with a bare PATH; put mise's shims and brew first."""
    extra = [
        str(HOME / ".local/share/mise/shims"),
        str(HOME / ".local/bin"),
        "/opt/homebrew/bin",
    ]
    os.environ["PATH"] = os.pathsep.join([*extra, os.environ.get("PATH", "")])


def run(*args):
    return subprocess.run(args, capture_output=True, text=True, check=True).stdout


def attempt(*args):
    """For commands whose failure is an answer, not an error."""
    return subprocess.run(args, capture_output=True, text=True, check=False)


def online(timeout=5):
    return attempt("online", "-q", str(timeout)).returncode == 0
