# Review of `tests/activation-watch.bats`: nine defects

### 1. LIVE-ONLY test: the filename check is satisfied by axis 1, not by the parity axis

- **What:** The fixture is not `.done`-marked, so the filename the test greps for is printed by the axis-1 FRESH partition whatever the parity axis does.
- **Where:** lines 91 and 94
  - `  stage "12-only-live-activate.sh"`
  - `  printf '%s' "$output" | grep -q '12-only-live-activate.sh'`
- **Why it is wrong:**
  - The section header (lines 84–87) says axis-2 fixtures are `.done`-marked so that axis 1 stays silent. This one is not.
  - Since M3, every un-run fresh file is named under FRESH. So line 94 passes even if the parity axis drops or misnames the file.
  - Line 95 only proves that the token `LIVE-ONLY` appears somewhere in the output.
  - A parity axis that prints a LIVE-ONLY heading but no filename passes this test.

### 2. CONTENT-DRIFT test: same wrong-reason pass

- **What:** The live-side fixture is not `.done`-marked, so the drift filename is printed by axis 1 regardless of whether drift was detected for it.
- **Where:** lines 109 and 112
  - `  printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"`
  - `  printf '%s' "$output" | grep -q '07-drift-activate.sh'`
- **Why it is wrong:** The FRESH partition always names `07-drift-activate.sh`. A parity axis that prints a `CONTENT-DRIFT` token without attributing it to this file passes lines 112–113.

### 3. M4 fixture builds a checkout *ahead* of trunk, not behind it

- **What:** The M4 fixture does not model deploy lag. The file stays in HEAD's own history, so the test cannot tell trunk adjudication apart from a local-history lookup.
- **Where:** lines 234–237
  - `  # the checkout is BEHIND trunk for this path — the deploy-lag shape`
  - `  ( cd "$w"; git rm -q docs/activation/pending-activation/landed-activate.sh; git commit -q -m drop`
  - `    git reset -q --hard HEAD~1; git rm -q --cached docs/activation/pending-activation/landed-activate.sh`
  - `    rm -f docs/activation/pending-activation/landed-activate.sh; git commit -q -m "checkout behind" ) >/dev/null 2>&1`
- **Why it is wrong:**
  - The `drop` commit is discarded by `reset --hard HEAD~1`, and nothing is pushed or fetched.
  - The end state is `origin/main` = base, with local main one commit *ahead* (it deletes the file). The checkout is not behind.
  - `landed-activate.sh` still exists in `HEAD~1`. So an adjudicator that checks the checkout's own history (for example `git log -- <path>` on HEAD) answers "committed" and passes.
  - In the real shape the M4 header describes, the file was added on `origin/main` past HEAD. That same adjudicator would find nothing there and emit the "never committed / cp live->repo" verdict that M4 exists to prevent.

### 4. DISABLED vs NOT-LOADED: neither run checks that the other tag is absent

- **What:** The test claims the two states are distinguished, but each run only checks that its own tag is present.
- **Where:** lines 317 and 319
  - `  printf '%s' "$output" | grep -q 'com.claude.log-rotation \[DISABLED\]'`
  - `  printf '%s' "$output" | grep -q 'com.claude.log-rotation \[NOT-LOADED\]'`
- **Why it is wrong:** A hook that prints both `[DISABLED]` and `[NOT-LOADED]` for every unloaded label passes both runs. Such a hook does not distinguish the states, and still sends the operator to `bootstrap` for a disabled label, which is exactly the failure the comment on lines 311–313 describes.

### 5. UNREADABLE-trunk test does not exclude either guessed verdict and does not check the file is named

- **What:** The only assertion is that the token `UNCONFIRMED` appears.
- **Where:** line 265 — `  printf '%s' "$output" | grep -q 'UNCONFIRMED'`
- **Why it is wrong:**
  - The comment (lines 259–261) says that guessing either way is wrong, but no assertion rules out either guess. Output with `UNCONFIRMED` plus `UNDEPLOYED-MIRROR` (guessed "on trunk") passes. So does output with `UNCONFIRMED` plus a confirmed LIVE-ONLY "never committed" line (guessed "absent").
  - `orphan-activate.sh` is never required to appear. A generic "trunk UNCONFIRMED" banner that drops the file satisfies the "still reported" claim.

### 6. M5 kill switch has no positive assertion

- **What:** The test claims `CC_ACTIVATION_INERT_SCOPE=claude` restores the com.claude-only pattern, but it only asserts that nothing is printed.
- **Where:** line 327 — `  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false`
- **Why it is wrong:**
  - The fixture contains only a com.chrisren label, and there is no com.claude label that must still be reported.
  - So a kill switch that turns axis 3 off entirely passes. So does a hook that exits early when that variable is set, since status is not checked.

### 7. M3 kill switch does not verify "exactly"

- **What:** The test never checks that the stale entry is still named under the restored filter.
- **Where:** lines 208–209
  - `  printf '%s' "$output" | grep -q 'staged >24h and NOT run'`
  - `  ! printf '%s' "$output" | grep -q 'b-new-activate.sh' || false`
- **Why it is wrong:** `a-old-activate.sh` is never asserted, and status is not checked. A kill switch that prints the legacy header but names nothing (or the wrong set) passes, so "restores the >24h filter exactly" is not tested.

### 8. The M4 "never committed" negative is pinned to one exact rendering

- **What:** The guard only fires if the LIVE-ONLY line matches one literal string, so it does not cover the misclassification it claims to exclude.
- **Where:** line 242 — `  ! printf '%s' "$output" | grep -q "LIVE-ONLY — never committed, one .rm. from unrecoverable: landed-activate.sh" || false`
- **Why it is wrong:**
  - If the hook words or formats its LIVE-ONLY verdict differently (other prefix text, dash, separator, or the filename on its own line), this negative can never match.
  - A hook that reports `landed-activate.sh` as both UNDEPLOYED-MIRROR and LIVE-ONLY would then pass.
  - The sibling assertions at lines 253, 255, 275 and 276 use the bare `LIVE-ONLY` / `UNDEPLOYED-MIRROR` tokens instead.

### 9. SYMLINK test: the `~/.claude` negative cannot fire, and the FALLBACK_REPO claim is unasserted

- **What:** The fixture cannot produce the `~/.claude` failure it guards against, and nothing distinguishes THIS checkout from FALLBACK_REPO.
- **Where:** lines 149–150
  - `  printf '%s' "$output" | grep -q "$REPO/docs/activation/pending-activation"`
  - `  ! printf '%s' "$output" | grep -q '\.claude/docs/activation'`
- **Why it is wrong:**
  - The symlink is created in `$BATS_TEST_TMPDIR`, not under `~/.claude`. An un-dereferenced `BASH_SOURCE` therefore resolves near the tmpdir and never to `~/.claude/docs/activation`, so line 150 always passes.
  - Line 148 claims "not the FALLBACK_REPO shared checkout", but no assertion checks that.
  - When the suite is run from the shared checkout itself (`REPO` == FALLBACK_REPO), a hook that fails to dereference and falls back prints the same path, and line 149 passes.
