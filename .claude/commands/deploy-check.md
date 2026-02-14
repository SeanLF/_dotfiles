# Pre-Deploy Safety Check

Run this checklist before deploying. Report findings for each item and only proceed if all checks pass.

## 1. Migration Safety

- Are there pending migrations? List them.
- Do any migrations rename or drop columns? If so, will old code break if it runs against the new schema during rollout?
- Can each migration be rolled back safely?
- Is migration ordering correct (no forward references)?

## 2. Deploy Target Completeness

- What files changed since last deploy? (`git diff` against deployed SHA)
- Based on what changed, which resources need updating? (services, timers, containers, configs)
- Does the deploy script/command target ALL affected resources?
- Are there any systemd timers or scheduled jobs that reference changed code?

## 3. Dependency Changes

- Were any dependencies added, removed, or upgraded?
- For upgrades: review changelogs for breaking changes
- For new dependencies: any known security issues?

## 4. Deploy Mechanism

- Will the deploy actually trigger a new container/service restart? (Check for stale tag issues like `:latest` not changing)
- Is the git SHA or version tag correctly propagated to the deploy trigger?

## 5. Rollback Plan

- What's the rollback command if this deploy fails?
- Are there any irreversible changes (data migrations, external API calls) that would make rollback incomplete?

## Output

For each section:
- **Status**: pass / warning / fail
- **Details**: what was checked and what was found

Final verdict: **deploy** or **hold** (with reason).
