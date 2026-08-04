set shell := ["bash", "-euo", "pipefail", "-c"]

# File discovery lives inside recipes (not `just` variables) because `git ls-files`
# returns newline-separated paths and a multiline just variable expanded inline
# makes bash interpret every path after the first as a new command — which will
# happily *execute* scripts like `bin/maint` instead of passing them as arguments.
# Using `xargs` keeps things literal and lazy-evaluated.

shell_pathspec := "'*.sh' '*.bash' 'bin/' ':!:bin/nextdns-configure'"

# Default: show available recipes
_default:
    @just --list

# Run all lint checks across the whole repo (not just staged files)
lint:
    git ls-files -z -- {{shell_pathspec}}   | xargs -0 mise x -- shellcheck
    git ls-files -z -- {{shell_pathspec}}   | xargs -0 mise x -- shfmt -d -i 2 -ci
    mise x -- ruff check bin/nextdns-configure
    git ls-files -z -- '*.toml'             | xargs -0 mise x -- taplo fmt --check
    # prettier 3.1.0+ hard-errors on explicitly-passed symlinks (glob-expanded ones it skips
    # silently); drop symlinked tracked files so linked skills don't fail the check.
    git ls-files -z -- '*.md' '*.json' '*.yml' '*.yaml' \
      | while IFS= read -r -d '' f; do [ -L "$f" ] || printf '%s\0' "$f"; done \
      | xargs -0 mise x -- prettier --check

# Run the test suites. Free and offline; tests/probe-*.sh are opt-in and cost
# tokens, so they are deliberately not here.
test:
    bash tests/test-review-gate.sh
    bash tests/test-tailscale-dns.sh
    python3 .claude/hooks/test-hooks.py

# Audit the machine for drift without making changes
dry-run:
    ./setup.sh --dry-run

# Full pre-push gate: lint everything + verify setup.sh still parses and runs
check: lint test dry-run

# Auto-fix everything that has an auto-fixer. Leaves the repo lint-clean.
fmt:
    git ls-files -z -- {{shell_pathspec}}   | xargs -0 mise x -- shfmt -w -i 2 -ci
    mise x -- ruff check --fix bin/nextdns-configure
    git ls-files -z -- '*.toml'             | xargs -0 mise x -- taplo fmt
    git ls-files -z -- '*.md' '*.json' '*.yml' '*.yaml' | xargs -0 mise x -- prettier --write

# Install dev tools (via mise) and activate git hooks (via lefthook).
# Run this once after cloning.
deps:
    mise install
    mise x -- lefthook install
