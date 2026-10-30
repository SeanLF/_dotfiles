"""When an unattended daily job is due: once a day, while the user is away."""

import re
from datetime import date

from . import run

IDLE_SECONDS = 900
OVERDUE_DAYS = 2


def idle_seconds():
    m = re.search(r'"HIDIdleTime" = (\d+)', run("ioreg", "-c", "IOHIDSystem"))
    return int(m[1]) / 1e9 if m else 0


def due(last_run, today, idle):
    """Not twice a day; otherwise only after 15 idle minutes, so nothing changes
    under the user, unless 2 days have passed. `idle` is called only if needed."""
    if last_run == today:
        return False
    if last_run and (today - last_run).days >= OVERDUE_DAYS:
        return True
    return idle() >= IDLE_SECONDS


def last_run(path):
    return date.fromisoformat(path.read_text().strip()) if path.exists() else None
