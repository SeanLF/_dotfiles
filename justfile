set shell := ["bash", "-euo", "pipefail", "-c"]

# File discovery lives inside recipes, piped through xargs, not in a `just`
# variable: a multiline variable expanded inline makes bash interpret every
# path after the first as a new command, executing it instead of passing it.

shell_pathspec := "'*.sh' '*.bash' 'bin/' ':!:bin/nextdns-configure' ':!:bin/cache-meter' ':!:bin/codex-config'"

# Default: show available recipes
_default:
    @just --list

# Run all lint checks across the whole repo (not just staged files)
lint:
    git ls-files -z -- {{shell_pathspec}}   | xargs -0 mise x -- shellcheck
    git ls-files -z -- {{shell_pathspec}}   | xargs -0 mise x -- shfmt -d -i 2 -ci
    mise x -- ruff check bin/nextdns-configure bin/cache-meter bin/codex-config
    git ls-files -z -- '*.toml'             | xargs -0 mise x -- taplo fmt --check
    # prettier 3.1+ hard-errors on explicitly-passed symlinks; drop them so linked skills don't fail.
    git ls-files -z -- '*.md' '*.json' '*.yml' '*.yaml' \
      | while IFS= read -r -d '' f; do [ -L "$f" ] || printf '%s\0' "$f"; done \
      | xargs -0 mise x -- prettier --check

# Run the test suites; tests/probe-*.sh are opt-in (cost tokens) and excluded.
test:
    bash tests/test-review-gate.sh
    bash tests/test-codex-hooks.sh
    bash tests/test-codex-config.sh
    bash tests/test-raycast-dns.sh
    python3 .claude/hooks/test-hooks.py

# Audit the machine for drift without making changes
dry-run:
    ./setup.sh --dry-run

# Full pre-push gate: lint everything + verify setup.sh still parses and runs
check: lint test dry-run

# Auto-fix everything that has an auto-fixer. Leaves the repo lint-clean.
fmt:
    git ls-files -z -- {{shell_pathspec}}   | xargs -0 mise x -- shfmt -w -i 2 -ci
    mise x -- ruff check --fix bin/nextdns-configure bin/cache-meter bin/codex-config
    git ls-files -z -- '*.toml'             | xargs -0 mise x -- taplo fmt
    git ls-files -z -- '*.md' '*.json' '*.yml' '*.yaml' | while IFS= read -r -d '' f; do [ -L "$f" ] || printf '%s\0' "$f"; done | xargs -0 mise x -- prettier --write

# Install dev tools (mise) and activate git hooks (lefthook). Run once after cloning.
deps:
    mise install
    mise x -- lefthook install
