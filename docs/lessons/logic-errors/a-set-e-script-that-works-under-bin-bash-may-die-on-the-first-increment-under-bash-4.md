---
title: A set -e script that works under /bin/bash may die on the first ((i++)) under bash 4+
date: 2026-09-13
category: logic-errors
module: bin/online, any #!/bin/bash script
problem_type: silent_regression
severity: medium
applies_when:
  - a reviewer or linter flags `((var++))` under `set -e` and the script "obviously works"
  - changing a shebang from /bin/bash to /usr/bin/env bash, or running a script with brew's bash
  - a set -e loop exits on its first iteration with status 1 and no message
tags: [bash, set-e, errexit, arithmetic, bash-3.2, shebang, macos]
---

## The lesson

`((count++))` from zero evaluates to 0, which is a non-zero exit status. Under
`set -e`, bash 5 exits there; macOS `/bin/bash` 3.2 carries on. A script can be
correct on one and dead on the other with no change to its text, so a negative
control that runs the old code has to run it under the interpreter the claim is
about.

## The measurement

`bin/online` retries a ping once a second until a timeout. Its loop body starts
with `((count++))`. A reviewer called it critical: the first failed ping would
kill the script before the retry loop ran, so the maintenance script's offline
guard was one ping, not a five second wait.

A one-line control confirmed it, in the PATH bash:

```
bash -c 'set -e; count=0; ((count++)); echo survived'   # exit 1, nothing printed
```

Then a test with a failing `ping` shim ran the unmodified script and it pinged
five times. The shebang is `#!/bin/bash`, and that is 3.2:

| interpreter                | `set -e; count=0; ((count++)); echo survived` |
| -------------------------- | --------------------------------------------- |
| /bin/bash 3.2.57           | prints, exit 0                                |
| /opt/homebrew/bin/bash 5.3 | exits 1                                       |

The bug was latent, not live. The fix stands because it removes a dependency
on 3.2 semantics that brew's bash on PATH does not share, but "critical" was
wrong and so was my first report of it.

## Guidance

- Write the increment as `count=$((count + 1))`. It has exit status 0 on every
  bash.
- When a finding says "under set -e this exits", check which bash. A macOS
  machine has two: `/bin/bash` (3.2, frozen for licence reasons) and whatever
  brew or mise put on PATH. Shebangs pick the first; `bash script` picks the
  second.
- A regression test for a bash-version-dependent bug must invoke the strict
  interpreter explicitly (`bash "$ROOT/bin/online"`), or it passes on the old
  code and measures nothing.

## Related

- [[a-pipeline-under-set-e-reports-only-its-last-stage]]
- [[exit-inside-a-command-substitution-cannot-stop-the-caller]]
- [[negative-control-the-harness-before-believing-its-number]]
