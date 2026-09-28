I found four defects, listed most certain first. Line numbers are counted from the pasted file.

## 1. The M5 kill-switch test can only pass by absence, so it cannot tell "scope restored" from "axis dead"

- **What:** The test asserts only that `CLAIMED-DONE BUT INERT` is absent, so any hook output without that string passes it.
- **Where:** line 329
  ```
    ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
  ```
- **Why it is wrong:** The test claims `CC_ACTIVATION_INERT_SCOPE=claude` "restores the com.claude-only pattern". It never checks that a `com.claude.*` label is still detected, and it never checks the exit status or any output. It passes if:
  - the axis-3 check crashes;
  - the axis is disabled outright;
  - the stub is never invoked;
  - the hook prints nothing at all.

  A regression that turns axis 3 off for every scope goes unnoticed. Compare the M3 and M4 kill-switch tests (lines 210 and 277), which each carry a positive assertion.

## 2. The axis-2 tests say their fixtures are `.done`-marked, but two are not, so axis 1 satisfies the name assertions

- **What:** The header says axis 1 is silenced by `.done` markers so each finding is attributable to parity alone. The LIVE-ONLY and CONTENT-DRIFT fixtures have no `.done` marker.
- **Where:**
  - line 84: `# Fixtures are \`.done\`-MARKED throughout, so axis 1 stays silent and every finding below is`
  - line 92: `  stage "12-only-live-activate.sh"`
  - line 95: `  printf '%s' "$output" | grep -q '12-only-live-activate.sh'`
  - line 110: `  printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"`
  - line 113: `  printf '%s' "$output" | grep -q '07-drift-activate.sh'`
- **Why it is wrong:** The files are fresh and un-run. Since M3, axis 1 lists them under FRESH, as the comment at lines 86–87 itself says. The filename greps at lines 95 and 113 therefore pass from axis-1 output even if axis 2 never names the file. In these tests only the keyword grep (`LIVE-ONLY`, `CONTENT-DRIFT`) is attributable to parity.

## 3. Two tests use the same fixture shape but expect different verdicts

- **What:** Both tests stage a live script that is absent from a plain, non-git mirror directory. The axis-2 test expects `LIVE-ONLY`; the M4 test expects `UNCONFIRMED`.
- **Where:**
  - line 96: `  printf '%s' "$output" | grep -q 'LIVE-ONLY'` (mirror is `mkdir -p "$M"`, line 91)
  - line 267: `  printf '%s' "$output" | grep -q 'UNCONFIRMED'` (mirror is `mkdir -p "$BATS_TEST_TMPDIR/bare-mirror"`, line 264)
- **Why it is wrong:** Lines 261–263 say a non-checkout mirror has no trunk ref, and that answering "absent" is a wrong guess. By that rule the line 96 fixture should yield `UNCONFIRMED`, not the "unrecoverable class". So one of two things holds:
  - The hook's `UNCONFIRMED` output also contains the word `LIVE-ONLY`. Then line 96 cannot tell "provably never committed" from "could not check", and the test named "the unrecoverable class" passes for the wrong reason.
  - The hook emits only `UNCONFIRMED` for that fixture. Then line 96 fails, and the test is stale relative to M4.

  Nothing in the file establishes which.

## 4. The M4 "never 'never committed'" check is a long literal that no test ever shows the hook emits

- **What:** The only guard that the misleading LIVE-ONLY verdict is absent is a negative grep for one exact sentence.
- **Where:** line 244
  ```
    ! printf '%s' "$output" | grep -q "LIVE-ONLY — never committed, one .rm. from unrecoverable: landed-activate.sh" || false
  ```
- **Why it is wrong:** Every positive assertion for that verdict greps only the bare token `LIVE-ONLY` (lines 96, 255, 277). Wording, punctuation, or a different filename list would make this negative pass while the hook still emits a LIVE-ONLY line for a file that is on trunk. The test's core claim, that the file is not reported as never committed, then goes unchecked. Lower confidence than items 1–3, because the hook's exact text is not visible here.
