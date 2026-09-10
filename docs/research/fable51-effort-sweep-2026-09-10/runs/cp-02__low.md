Reviewing the bats file text only, as instructed.

**Defect 1: Negated grep assertions without `|| false` never fail the test.**

- **Where:** line 23: `  ! printf '%s' "$output" | grep -q '^  FAIL'`
- **Where:** line 80: `  ! printf '%s' "$output" | grep -q 'done-c.sh'`
- **Where:** line 149: `  ! printf '%s' "$output" | grep -q '\.claude/docs/activation'`
- **Why it is wrong:** Bats detects failures through bash's `set -e` semantics, and bash explicitly exempts a `!`-negated pipeline from errexit. If the selftest output contains a `  FAIL` line, if the `.done`-marked `done-c.sh` is wrongly named, or if the symlinked hook resolves the mirror under `~/.claude`, these lines evaluate false and the test continues and passes anyway. The file itself knows this idiom is unsafe: every other negated assertion (lines 52, 80's sibling at M3, M4, M5 tests) appends `|| false`. These three are the exceptions, so the selftest-has-no-FAIL guard, the `.done` exclusion in the mixed-queue test, and the "never ~/.claude" claim of the symlink regression test are all silently unenforced.

**Defect 2: Axis-2 fixtures that the header says are `.done`-marked are not, so their name assertions pass via axis 1.**

- **Where:** line 84 (`# Fixtures are \`.done\`-MARKED throughout, so axis 1 stays silent and every finding below is`) versus line 90: `  stage "12-only-live-activate.sh"` and line 108: `  printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"`, asserted at line 93: `  printf '%s' "$output" | grep -q '12-only-live-activate.sh'` and line 111: `  printf '%s' "$output" | grep -q '07-drift-activate.sh'`
- **Why it is wrong:** Neither fixture gets a `.done` marker, and both have a current mtime. Under the M3 partitioning behaviour tested later in this same file, a fresh un-done script is always named in the FRESH partition by axis 1. So the "script is named" assertion in the LIVE-ONLY and CONTENT-DRIFT tests is satisfied by axis 1 regardless of whether axis 2 ran, contradicting the stated isolation contract. Only the `LIVE-ONLY` / `CONTENT-DRIFT` keyword greps still exercise axis 2, and the CONTENT-DRIFT test additionally omits the `[ "$status" -eq 0 ]` check that every neighbour has.

No other defects found. The `mkmirror` and M4 git sequences produce the intended shape (trunk has the file, checkout does not), the `lcstub` generator emits valid bash for empty label lists, and the remaining assertions test what they claim.
