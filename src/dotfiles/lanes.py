"""Side panes that run steps one at a time as the main pane hands them out.

A fixed set of panes, so Rex's layout doesn't reflow every time a step that
takes a second starts and ends. Each pane runs lib/maintenance/lane.sh; the
main pane and a lane talk through two files in the lane's folder: `job` (what
to run next) and `result` (its exit code).
"""

import shutil
import subprocess
import time

from . import REPO, rex

WORKER = REPO / "lib/maintenance/lane.sh"


def put(path, text):
    """Write so the reader never sees half a file."""
    tmp = path.with_suffix(".tmp")
    tmp.write_text(text)
    tmp.rename(path)


def settle(timeout=2.0):
    """Wait for this pane to stop resizing after splits, so a live display
    measures the width it will keep."""
    last, still, end = None, 0, time.monotonic() + timeout
    while time.monotonic() < end and still < 3:
        size = shutil.get_terminal_size()
        still = still + 1 if size == last else 0
        last = size
        time.sleep(0.1)


class Lanes:
    def __init__(self, count, run_dir, session, anchor, cwd):
        self.session, self.run_dir, self.cwd = session, run_dir, cwd
        self.folders, self.blocks, self.idle, self.failed, self.node = (
            [],
            [],
            [],
            set(),
            {},
        )
        self.anchor, self.direction = anchor, "right"
        for _ in range(count):
            self.open()
        settle()

    def open(self):
        k = len(self.folders)
        folder = self.run_dir / "lanes" / str(k)
        folder.mkdir(parents=True)
        block = rex.split(
            self.anchor, self.direction, self.cwd, [str(WORKER), str(folder)]
        )
        self.folders.append(folder)
        self.blocks.append(block)
        self.idle.append(k)
        self.anchor, self.direction = block, "below"

    def give(self, node, title, command, log):
        """script(1) keeps the pane a terminal and fills the log as it goes."""
        k = self.idle.pop(0)
        self.node[k] = node
        wrapped = ["script", "-q", "-F", str(log), *command]
        put(self.folders[k] / "job", "\n".join([title, *wrapped]) + "\n")

    def finished(self):
        """(node, exit code) for each job that ended since the last call."""
        done = []
        for k, folder in enumerate(self.folders):
            result = folder / "result"
            if result.exists():
                code = int(result.read_text())
                result.unlink()
                done.append((self.node.pop(k), code))
                if code != 0:
                    # Kept as it is, so the pane still shows the failure; a
                    # fresh lane takes its place.
                    self.failed.add(k)
                    self.open()
                else:
                    self.idle.append(k)
        return done

    def retire_idle(self):
        """Close idle lanes with nothing left to give them; ones that failed stay."""
        for k in list(self.idle):
            if k not in self.failed:
                self.stop(k)
        self.idle = [k for k in self.idle if self.blocks[k] is not None]

    def stop(self, k):
        if self.blocks[k] is None:
            return
        put(self.folders[k] / "job", "stop\n")
        rex.wait(self.blocks[k])
        if k not in self.failed:
            rex.close_block(self.session, self.blocks[k])
            self.blocks[k] = None

    def close(self):
        """Stop every lane still open; one that ran a failing step stays to read."""
        for k in range(len(self.blocks)):
            self.stop(k)


class Background:
    """The same jobs as background processes, output only to their logs: for a
    run nobody follows pane by pane (an agent, a pipe, a terminal without Rex)."""

    def __init__(self, count):
        self.idle, self.running = list(range(count)), {}

    def give(self, node, title, command, log):
        k = self.idle.pop(0)
        with log.open("w") as out:
            proc = subprocess.Popen(
                command, stdin=subprocess.DEVNULL, stdout=out, stderr=subprocess.STDOUT
            )
        self.running[k] = (node, proc)

    def finished(self):
        done = []
        for k, (node, proc) in list(self.running.items()):
            if proc.poll() is not None:
                del self.running[k]
                self.idle.append(k)
                done.append((node, proc.returncode))
        return done

    def retire_idle(self):
        pass

    def close(self):
        pass
