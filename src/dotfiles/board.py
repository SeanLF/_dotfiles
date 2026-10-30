"""The run as its dependency graph: one row per node, grouped by when it can start."""

import time

from rich.table import Table
from rich.text import Text

SPINNER = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"


def label(node):
    return node.removeprefix("step_").removeprefix("audit_").replace("_", " ")


def order(graph):
    """Every node, each after the ones it waits for."""
    done, out = set(), []
    while len(out) < len(graph):
        ready = sorted(
            n for n in graph if n not in done and all(d in done for d in graph[n])
        )
        if not ready:
            raise ValueError(f"dependency cycle among {sorted(set(graph) - done)}")
        out += ready
        done |= set(ready)
    return out


def waited_on(graph):
    """How many nodes wait on each, directly or through others."""
    below = {n: set() for n in graph}
    for node in reversed(order(graph)):
        for dep in graph[node]:
            below[dep] |= {node} | below[node]
    return {n: len(below[n]) for n in graph}


def layers(graph):
    """Nodes grouped by how many waits stand before them."""
    depth = {}
    for node in order(graph):
        depth[node] = 1 + max((depth[d] for d in graph[node]), default=-1)
    return [
        [n for n in order(graph) if depth[n] == k]
        for k in range(max(depth.values()) + 1)
    ]


def waits(graph, node, everything):
    """What a node waits for, short: a node waiting on all upgrades says so."""
    deps = graph[node]
    if len(deps) > 4 and set(deps) >= set(everything):
        return "all upgrades"
    return ", ".join(label(d) for d in deps)


class Board:
    def __init__(self, graph, upgrades, title):
        self.graph, self.upgrades, self.title = graph, upgrades, title
        self.state = dict.fromkeys(graph, "waiting")
        self.started, self.secs, self.ended_at, self.tick = {}, {}, {}, 0

    def set(self, node, state):
        if state == "running":
            self.started[node] = time.monotonic()
        else:
            self.secs[node] = int(time.monotonic() - self.started[node])
            self.ended_at[node] = time.monotonic()
        self.state[node] = state

    def placed(self, layer):
        """A group's rows: finished in the order they finished, then running, then
        waiting, so the active ones sit at the bottom like a log."""
        rank = {"done": 0, "failed": 0, "running": 1, "waiting": 2}
        return sorted(
            layer,
            key=lambda n: (
                rank[self.state[n]],
                self.ended_at.get(n, self.started.get(n, 0)),
                n,
            ),
        )

    def ended(self, node):
        return self.state[node] in ("done", "failed")

    def __rich__(self):
        self.tick += 1
        counts = {
            k: sum(v == k for v in self.state.values())
            for k in ("running", "done", "failed", "waiting")
        }
        table = Table.grid(padding=(0, 1))
        table.title = Text.assemble(
            (self.title, "bold"),
            "  ",
            (" · ".join(f"{n} {k}" for k, n in counts.items() if n), "dim"),
        )
        table.title_justify = "left"
        # Fixed widths for the number and icon, so a narrow pane trims names, not them.
        table.add_column(width=1, no_wrap=True)
        table.add_column(width=1, no_wrap=True)
        table.add_column(no_wrap=True, overflow="ellipsis", min_width=8)
        table.add_column(no_wrap=True, overflow="ellipsis")
        for k, layer in enumerate(layers(self.graph)):
            for i, node in enumerate(self.placed(layer)):
                state = self.state[node]
                step = Text(str(k + 1) if i == 0 else "", style="dim")
                if state == "waiting":
                    icon, name, secs = (
                        Text("·", "dim"),
                        Text(label(node), "dim"),
                        Text(""),
                    )
                    after = waits(self.graph, node, self.upgrades)
                    note = Text(f"after {after}" if after else "", "dim")
                else:
                    icon = {
                        "running": Text(SPINNER[self.tick % len(SPINNER)], "cyan"),
                        "done": Text("✓", "green"),
                        "failed": Text("✗", "yellow"),
                    }[state]
                    elapsed = self.secs.get(
                        node,
                        int(
                            time.monotonic() - self.started.get(node, time.monotonic())
                        ),
                    )
                    name, secs, note = (
                        Text(label(node)),
                        Text(f"{elapsed}s", "dim"),
                        Text(""),
                    )
                table.add_row(step, icon, name, Text.assemble(secs, "  ", note))
        return table
