set shell := ["bash", "-euo", "pipefail", "-c"]

# File discovery lives inside recipes, piped through xargs, not in a `just`
# variable: a multiline variable expanded inline makes bash interpret every
# path after the first as a new command, executing it instead of passing it.


# Default: show available recipes
_default:
    @just --list

# Tracked files of one content type, NUL-separated: bin/ mixes shell and Python
# without extensions, so names can't tell them apart (lefthook uses file_types).
_files type:
    @git ls-files -z | while IFS= read -r -d '' f; do [ -L "$f" ] || [ "$(file -b --mime-type "$f")" != "{{type}}" ] || printf '%s\0' "$f"; done

# Run all lint checks across the whole repo (not just staged files)
lint:
    just _files text/x-shellscript | xargs -0 mise x -- shellcheck
    just _files text/x-shellscript | xargs -0 mise x -- shfmt -d -i 2 -ci
    { git ls-files -z -- '*.py'; just _files text/x-script.python; } | xargs -0 mise x -- ruff check
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
    python3 .claude/hooks/test-hooks.py
    uv run --group dev pytest -q

# Audit the machine for drift without making changes
dry-run:
    ./setup.sh --dry-run

# Full pre-push gate: lint everything + verify setup.sh still parses and runs
check: lint test dry-run

# Auto-fix everything that has an auto-fixer. Leaves the repo lint-clean.
fmt:
    just _files text/x-shellscript | xargs -0 mise x -- shfmt -w -i 2 -ci
    { git ls-files -z -- '*.py'; just _files text/x-script.python; } | xargs -0 mise x -- ruff check --fix
    git ls-files -z -- '*.toml'             | xargs -0 mise x -- taplo fmt
    git ls-files -z -- '*.md' '*.json' '*.yml' '*.yaml' | while IFS= read -r -d '' f; do [ -L "$f" ] || printf '%s\0' "$f"; done | xargs -0 mise x -- prettier --write

# Install dev tools (mise) and activate git hooks (lefthook). Run once after cloning.
deps:
    mise install
    mise x -- lefthook install
