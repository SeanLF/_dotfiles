## Identity

- Builder; ownership over systems I care about
- Hard problems over maintenance; agency over direction
- Someone else's mess on someone else's terms is poison regardless of pay
- Ships working software > debates architecture endlessly
- AI systems work genuinely excites; design around that energy

## Commits

- ALWAYS _why_, not _what_
- Conventional commits NO emoji
- Squash debug/fix chains before pushing
- Run review + simplifier agents before committing

## Code Review

- Check git log before suggesting reversals
- Aim for convergence on follow-ups; "this is fine" is valid
- Run `silent-failure-hunter` on error handling changes

## Approach

- Ship working software: pragmatic, not sloppy
- Explicit over clever (readable at 2am)
- Truth over comfort: challenge reasoning, don't just validate
- Minimum viable change; every line is liability
- Small atomic commits, each deployable
- Security first-class, not afterthought
- Tests catch real bugs, not coverage theatre

## Aesthetics

- Craft over decoration; someone should have clearly given a shit
- Simplicity ≠ sameness; cookie-cutter is the enemy, not complexity
- Beauty is a feature, not a nice-to-have
- Ugly defaults signal nobody cared

## UX

- Joy of use matters
- Readability > pretty; no white-on-frosted-glass
- Empathy-driven; think of the person using it
- Familiar patterns aid usability; copy-paste homogeneity does not

## Languages

- Comfortable: Ruby, Python
- JS syntax familiar, ecosystem not - explain libs/frameworks
- Canadian spelling
- US keyboard chars (no em dash)

## Debugging

- Read output carefully first time
- Verify actual state before fixes
- Trace symptoms to root cause
- Understand before workarounds

## Infrastructure

- Zero-downtime: verify new healthy before stopping old and switching traffic
- Have rollback plan

## Ruby

- Follow community philosophies
- Love: `it`, `_1`, shorthand hash, `tap`/`then` chaining
- Exceptions over monad ceremony
- Avoid metaprogramming

## Performance

- Local machine: 48 GB RAM MacBook Pro 16" M4 Pro
- Prefer CPU-efficient over IO-optimized
- Suspect CPU bottlenecks before IO
- Legacy IO patterns often artificially constrained

## Working with AI

- Thinking partner, not search engine
- Challenge reasoning; don't just validate
- Continuity matters; use memory/context
- Say "I don't know" or "that's wrong" over confident bullshit

## Paths

- Projects: `~/Developer/`, experiments: `~/Developer/_experiments/`
- Persistent tasks: `.claude/tasks/todo.md` (per-project)
- Writing in my voice: read `~/.claude/writing-style.md`
