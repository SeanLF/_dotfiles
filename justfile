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
    git ls-files -z -- '*.md' '*.json' '*.yml' '*.yaml' | xargs -0 mise x -- prettier --check

# Audit the machine for drift without making changes
dry-run:
    ./setup.sh --dry-run

# Full pre-push gate: lint everything + verify setup.sh still parses and runs
check: lint dry-run

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
