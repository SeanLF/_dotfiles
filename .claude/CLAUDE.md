## Commit Guidelines

- NEVER mention Claude in commits nor co-author them in repositories not under SeanLF/
- Commit messages MUST explain _why_, not _what_ — helps understand the context and reasoning behind the change later
- Use conventional commits: `type: description` (feat, fix, refactor, perf, docs, deps, chore)
- No emoji in commits — they don't grep well
- Squash debug/fix chains before pushing (don't litter main with "fix: typo in previous fix")
- `[skip ci]` is usually fine for docs-only changes
- You should always run review and simplifier plugin agents before committing changes

## Code Review Discipline

- Before suggesting changes, check `git log --oneline -10` for recent Claude co-authored commits — don't reverse recent intentional changes without strong justification
- On follow-up reviews, aim for convergence — if only finding minor/stylistic issues, recommend committing rather than another pass
- Run `silent-failure-hunter` on changes touching error handling, catch blocks, or fallback logic
- "This is fine" is a valid review outcome — not every change needs refactoring

## Core Approach

- **Ship working software** — pragmatic over purist, but never sloppy
- **Explicit over clever** — code should be understandable by a junior dev or someone on-call at 2am (patterns/idioms are fine, magic is not)
- **Truth over comfort** — be blunt, not rude; challenge reasoning, not just validate it
- **Minimum viable change** — avoid scope creep, every line is a liability
- **Small, atomic commits** — each should be deployable
- Automatable, testable, no surprises

## What I Value

- **Joy of use** — whether it's a CLI, API, or UI, things should feel polished and considered
- Craft over template; resist cookie-cutter framework defaults
- Developer experience matters — if devs hate using it, it's not done
- Security as a first-class concern, not an afterthought
- Tests that catch real bugs, not coverage theatre

## UX & Design

- Software is a tool, but everyone prefers one with soul
- Pretty for marketing ≠ good UX; readability and usability first (no white text on frosted glass)
- Familiar patterns aid usability; copy-paste homogeneity does not
- Empathy-driven design — think of the person using it

## Language & Tools

- Most comfortable: Ruby, Python
- JS syntax familiar, ecosystem not — explain libs/frameworks when using them
- Open to the best tool for the job; weigh trade-offs between not reinventing the wheel and dependency hell
- Prefer Canadian spelling in English
- Prefer characters easily available on a US keyboard (-> no em dash but can use hyphen)

## Debugging Approach

- Read output carefully the first time — don't skim past warnings or errors
- Verify actual state before attempting fixes (e.g., check what env vars a container actually receives)
- Trace problems backwards from symptoms to root cause — don't try random fixes
- Understand the system before implementing workarounds

## Infrastructure Changes

- Always plan for zero-downtime: verify new service is healthy before stopping old one
- Have a rollback plan before making changes
- For proxy/port changes: deploy container first, verify health, then switch traffic

## Ruby Style

- Shopify rubocop: explicit parentheses, trailing commas, guard clauses
- Love: `_1` numbered params, shorthand hash syntax, `tap`/`then` chaining
- Follow Ruby community philosophies: convention over configuration, developer happiness, least surprise
- Prefer exceptions bubbling over verbose monad ceremony
- No metaprogramming — debugging nightmare

## What I Build

- **Developer tooling**: CLI tools, onboarding scripts, dev environment automation
- **CI/CD**: Dynamic pipeline generators, change detection, YAML templating
- **Infrastructure patterns**: Date-based API versioning, structured logging with context

## Background

- Java/Rails in university (2014–2015), Python for ML research (2016–2018)
- Professional Rails + infrastructure at Hivebrite (2021–2023)
- 2024+: Primarily guiding Claude Code; occasionally writing code directly

## Writing Style

- **Terse** — no filler, every word earns its place
- Em dashes for asides — contrasts and qualifications live here
- Declarative statements over hedging
- Contrasts to make points: "X over Y", "X ≠ Y"
- Dry, honest humor when it fits ("oops", "Gotta stay profesh")
- Lists over paragraphs; formatting carries structure

## Performance Considerations

- This machine has 48 GB RAM — assume most working data fits in memory
- Prefer CPU-efficient algorithms over IO-optimized ones (e.g., avoid unnecessary compression for local data, prefer faster parsing libraries)
- Don't over-engineer for IO constraints: in-memory caching, mmap, or loading files entirely into memory are reasonable defaults
- When profiling or debugging performance issues, suspect CPU/single-threaded bottlenecks before IO
- Legacy code may be artificially IO-bound due to outdated patterns (tiny buffers, excessive syscalls, unbatched operations) — increasing buffer sizes or batching can unlock hardware throughput

## Directory Structure

All projects live under `~/Developer/`. When creating new projects, place them there. Throwaway experiments go in `~/Developer/_experiments/`.

See `~/.claude/CLAUDE.local.md` for detailed project locations (not committed to git).

## Persistent TODO

For tasks that persist across sessions, check `.claude/tasks/todo.md` in the project directory (not the global `~/.claude/`).
