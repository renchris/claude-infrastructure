# Review of `tests/activation-watch.bats`: 8 defects

These are test defects: in each case an assertion can pass without proving what the test claims.

---

### 1. LIVE-ONLY test: the filename check can pass through axis 1 instead of the parity axis

- **What:** The fixture has no `.done` marker, so the check for the filename is satisfied by axis 1 whether or not the parity axis ever names the file.
- **Where:** line 91 `  stage "12-only-live-activate.sh"` and line 94 `  printf '%s' "$output" | grep -q '12-only-live-activate.sh'`
- **Why it is wrong:**
  - The section header (lines 84–87) says fixtures are `.done`-marked so that every finding is attributable to parity alone. It also says that since M3, freshness no longer buys silence.
  - Here an unmarked fresh file is always named in axis 1's FRESH partition, so line 94 passes regardless of parity.
  - Only the free-floating `LIVE-ONLY` label check depends on axis 2. A parity axis that printed the LIVE-ONLY header but named the wrong file, or no file, would still pass.

### 2. CONTENT-DRIFT test: same leak through axis 1

- **What:** Same leak as defect 1: the live drift fixture is unmarked, so the filename check is satisfied by axis 1.
- **Where:** line 109 `  printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"` and line 112 `  printf '%s' "$output" | grep -q '07-drift-activate.sh'`
- **Why it is wrong:**
  - `07-drift-activate.sh` is a fresh, not-done queue entry, so axis 1 names it under FRESH.
  - Line 112 therefore passes even if the drift finding never names the file.
  - Nothing ties the name to the `CONTENT-DRIFT` row.

### 3. Symlink test cannot reproduce the failure it guards against

- **What:** The fixture never recreates the failure it targets, so its negative check can never fire, and its positive check cannot tell the checkout from the fallback repo.
- **Where:** line 145 `  ln -s "$H" "$BATS_TEST_TMPDIR/linked.sh"`, line 149 `  printf '%s' "$output" | grep -q "$REPO/docs/activation/pending-activation"`, line 150 `  ! printf '%s' "$output" | grep -q '\.claude/docs/activation'`
- **Why it is wrong:**
  - An un-dereferenced `BASH_SOURCE` yields `~/.claude` only because the live symlink sits in `~/.claude/hooks/`.
  - Here the symlink sits directly in `$BATS_TEST_TMPDIR`. Broken dereferencing would therefore yield the parent of the tmpdir, never a `.claude` path, so line 150 is vacuous.
  - That bogus path has no `.git`, so the `.git`-gate falls through to the fallback repo. `CC_ACTIVATION_REPO` is not neutralized here, unlike at line 136.
  - When the suite runs from the shared checkout, the fallback repo is `$REPO`, so line 149 also passes. The comment's claim "not the FALLBACK_REPO shared checkout" is not checked, and the test goes green with dereferencing broken.

### 4. M4 fixture builds a checkout that is ahead of trunk, not behind it

- **What:** The fixture leaves the checkout one commit *ahead* of `origin/main`, not "BEHIND trunk" as the comment claims.
- **Where:** line 234 `  # the checkout is BEHIND trunk for this path — the deploy-lag shape` through line 237 `    rm -f docs/activation/pending-activation/landed-activate.sh; git commit -q -m "checkout behind" ) >/dev/null 2>&1` (including line 236 `    git reset -q --hard HEAD~1; git rm -q --cached docs/activation/pending-activation/landed-activate.sh`)
- **Why it is wrong:**
  - The `drop` commit is undone by `reset --hard HEAD~1`. The final commit is a local, unpushed deletion, and `origin/main` is never advanced. The result is the same as the simpler fixture on lines 270–271.
  - The file is therefore in the checkout's *own* HEAD history (the `base` commit).
  - An adjudicator that consults local history or any ref, rather than trunk, would answer "committed" and pass this test.
  - In the real deploy-lag shape, trunk has a commit the checkout has never seen. That adjudicator would get it wrong, and that shape is never constructed.

### 5. M4 negative check matches an exact phrase that is never shown to exist

- **What:** The only guard against `landed-activate.sh` *also* being listed as LIVE-ONLY is an exact-phrase negative that no other test confirms the tool ever produces.
- **Where:** line 242 `  ! printf '%s' "$output" | grep -q "LIVE-ONLY — never committed, one .rm. from unrecoverable: landed-activate.sh" || false`
- **Why it is wrong:**
  - The M4 positive control (line 253) and kill switch (line 275) only grep `LIVE-ONLY`, never this full string.
  - Any wording or layout difference defeats the negative: different punctuation, the name on a separate line, another name listed first, or the em dash JSON-escaped to `\u2014` in the additionalContext emit.
  - In any of those cases the file can be double-reported as UNDEPLOYED-MIRROR *and* LIVE-ONLY, and line 242 still passes.

### 6. M4 positive control cannot tell a confirmed LIVE-ONLY from an UNCONFIRMED one

- **What:** The positive control cannot distinguish "confirmed absent from trunk" from "trunk unreadable" (UNCONFIRMED).
- **Where:** line 253 `  printf '%s' "$output" | grep -q 'LIVE-ONLY'` (with fixture errors hidden by line 228 `    git add -A; git commit -q -m base; git push -q -u origin main ) >/dev/null 2>&1`)
- **Why it is wrong:**
  - Two tests use the same parity setup: a plain, non-checkout mirror with a live file missing from it.
  - The axis-2 LIVE-ONLY test (line 95) expects `LIVE-ONLY` from that setup, and the UNREADABLE test (line 265) expects `UNCONFIRMED`. So the unreadable-trunk verdict also prints `LIVE-ONLY`.
  - If the adjudicator maps "absent" to UNCONFIRMED, lines 253–255 still pass. The same happens if `mkmirror` silently failed to create `origin/main`, since all its output goes to `/dev/null` and is never checked.
  - The definitive "never committed" alarm this control claims to protect can therefore be degraded without detection.

### 7. M5 positive control passes if the hook crashes

- **What:** The test that should show the INERT axis "can go quiet" has no status or output assertion.
- **Where:** line 307 `  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false`
- **Why it is wrong:**
  - If the hook exits non-zero, or aborts while parsing the non-empty `launchctl list` output (a path only this test reaches), the output lacks the INERT row and the test passes.
  - A crash therefore reads as "went quiet." Compare the M3 control, which asserts `status 0` and empty output.

### 8. M5 kill switch test passes if the switch disables axis 3 entirely

- **What:** The kill-switch test asserts only an absence, so it passes if the switch turns axis 3 off entirely or the hook fails.
- **Where:** line 327 `  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false`
- **Why it is wrong:**
  - The test claims `CC_ACTIVATION_INERT_SCOPE=claude` "restores the com.claude-only pattern."
  - It never shows that a `com.claude.*` label is still flagged under the switch, and it does not check status.
  - A switch that disables the INERT axis, or a crash, yields no INERT row and passes.
