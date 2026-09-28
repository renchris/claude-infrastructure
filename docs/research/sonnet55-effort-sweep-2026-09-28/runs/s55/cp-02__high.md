I found one clear defect and three weaker ones where an assertion can pass without proving what it claims.

## Defects

**1. The axis-2 fixtures are not `.done`-marked, so the filename assertions pass on axis 1 alone.**
- **What:** The section header says every axis-2 fixture is `.done`-marked so that axis 1 stays silent, but the LIVE-ONLY and CONTENT-DRIFT fixtures are unmarked.
- **Where:**
  - line 93: `  stage "12-only-live-activate.sh"`
  - line 96: `  printf '%s' "$output" | grep -q '12-only-live-activate.sh'`
  - line 111: `  printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"`
  - line 114: `  printf '%s' "$output" | grep -q '07-drift-activate.sh'`
- **Why it is wrong:** Each fixture is a fresh, un-run activation with no `.done` marker. Axis 1 therefore lists it under the FRESH partition and names the file (per the M3 tests). The `grep -q '<filename>'` assertions pass from axis 1 even if axis 2 never names the file. In the CONTENT-DRIFT test the fixture copies are created directly in `$Q` with no marker at all. The suite's own header comment says this kind of isolation was the point. The `LIVE-ONLY` and `CONTENT-DRIFT` keyword greps are still axis-2-only, so the tests are not fully vacuous. The "named" claim is not attributable to the parity axis, though.

**2. The M5 positive control passes on a silent or crashed hook.**
- **What:** Its only assertion is a negated grep with no status check and no positive assertion, so it cannot tell "axis went quiet" from "hook produced nothing".
- **Where:** line 311: `  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false`
- **Why it is wrong:** If the hook errors out on the loaded-label path, or emits empty output for any other reason, `$output` lacks the string and the test passes. It is meant to show that the axis can go quiet correctly. It only shows that one string is absent.

**3. The M5 kill-switch test has the same vacuous shape.**
- **What:** Same as above: the only assertion is a negated grep, with no status check.
- **Where:** line 331: `  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false`
- **Why it is wrong:** A hook that crashes or prints nothing when `CC_ACTIVATION_INERT_SCOPE=claude` is set passes the test. It does not show that the kill switch restored the com.claude-only pattern.

**4. The M4 "never 'never committed'" negation depends on an exact long phrase that nothing else in the file confirms.**
- **What:** The negative assertion greps for one exact string, including an em dash and a `.rm.` wildcard, instead of the `LIVE-ONLY` token the rest of the file uses.
- **Where:** line 246: `  ! printf '%s' "$output" | grep -q "LIVE-ONLY — never committed, one .rm. from unrecoverable: landed-activate.sh" || false`
- **Why it is wrong:** The positive control (line 257, `grep -q 'LIVE-ONLY'`) only shows the token `LIVE-ONLY` appears. If the hook words the verdict even slightly differently, for example different punctuation, the label being `LIVE-ONLY:` alone, or different file-list formatting, the regression this test targets would still pass line 246. Only the `UNDEPLOYED-MIRROR` and `do NOT cp` positives at lines 244 and 248 would then guard it.
