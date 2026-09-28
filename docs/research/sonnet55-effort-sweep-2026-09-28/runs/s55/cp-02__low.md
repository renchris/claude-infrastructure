**Defect 1**

1. **What** — The axis-2 parity fixtures are not `.done`-marked, contrary to the section's stated design, so axis 1 fires alongside axis 2 and each name assertion is satisfied without the parity axis.
2. **Where** — Lines 92, 110 and 101 (the `--parity` test's `stage "only-live.sh"` has the same problem); line numbers are from my own count of the brief.
   - Line 92: `  stage "12-only-live-activate.sh"`
   - Line 110: `  printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"`
   - Line 101: `  printf '#!/bin/bash\n# committed\n' > "$M/09-only-repo-activate.sh"` is not affected, because its live queue is empty.
3. **Why it is wrong** — The section comment says "Fixtures are `.done`-MARKED throughout, so axis 1 stays silent and every finding below is attributable to the parity axis alone." In the LIVE-ONLY and CONTENT-DRIFT tests, the live script has no `.done` marker and is fresh, so axis 1 lists it under FRESH. That makes `grep -q '12-only-live-activate.sh'` and `grep -q '07-drift-activate.sh'` pass on axis-1 output even if axis 2 never names the file. Only the second grep (`LIVE-ONLY` or `CONTENT-DRIFT`) tests parity. The same applies to the `--parity` test's `grep -q 'only-live.sh'`, if `--parity` also emits axis-1 output. The comment's isolation claim is false for these tests.

**Defect 2 (lower confidence)**

1. **What** — The M4 negative assertion matches one hard-coded message string that no test in this file ever confirms the tool emits, so it can pass without checking anything.
2. **Where** — In the "M4: a live file that EXISTS on trunk…" test: `  ! printf '%s' "$output" | grep -q "LIVE-ONLY — never committed, one .rm. from unrecoverable: landed-activate.sh" || false`
3. **Why it is wrong** — The positive-control test only greps for `LIVE-ONLY` and the filename separately. If the tool words the finding even slightly differently (punctuation, dash, ordering), a wrongly emitted "never committed" verdict for a file that is on trunk would not match this long pattern. The negative would then pass vacuously, which is the failure the test claims to guard against.

I found no other defects I can point at in the code.
