# Review of `tests/activation-watch.bats`

I found six defects. The first four are certain. The last two depend on how the hook behaves, which isn't in this file, so treat them with somewhat lower confidence.

---

### 1. LIVE-ONLY test: the filename check can pass because of the wrong axis

**What:** The fixture is not `.done`-marked, so the age check (axis 1) names the file under FRESH. The filename assertion therefore passes whether or not the parity check (axis 2) reported it.

**Where:** line 91, `stage "12-only-live-activate.sh"`; line 94, `printf '%s' "$output" | grep -q '12-only-live-activate.sh'`

**Why it is wrong:**
- The section header (lines 84–87) says axis-2 fixtures are `.done`-marked "throughout" so that every finding comes from axis 2 alone.
- This fixture is fresh and unmarked. Since M3, fresh files are listed under FRESH rather than filtered out.
- Suppose axis 2 printed the `LIVE-ONLY` heading but listed no file, or a different file. Line 94 would still pass, because axis 1 printed the name.
- The test never shows that `LIVE-ONLY` is attached to this file.

### 2. CONTENT-DRIFT test: same problem

**What:** The drifted live fixture is also not `.done`-marked, so the filename assertion is satisfied by axis 1's FRESH listing.

**Where:** line 109, `printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"`; line 112, `printf '%s' "$output" | grep -q '07-drift-activate.sh'`

**Why it is wrong:**
- `07-drift-activate.sh` is fresh with no `.done` file, so axis 1 always names it.
- A drift check that printed a `CONTENT-DRIFT` heading but failed to name the diverged file would still pass.
- The test does not check the exit status either.

### 3. M5 POSITIVE CONTROL passes if the hook crashes

**What:** The test's only assertion is a negated grep. It has no status check and no check on the output, so a hook that crashes or prints nothing passes.

**Where:** line 307, `! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false`

**Why it is wrong:**
- The test claims to prove "the axis can go quiet".
- If the hook exits non-zero, or never runs the launchctl axis (for example, it errors on the stub), `$output` has no `CLAIMED-DONE BUT INERT`.
- The test then passes, so a broken axis 3 reads as a correctly quiet one.

### 4. M5 kill switch passes if the hook crashes

**What:** The only assertion is again a negated grep, with no status check and no positive evidence that the hook ran.

**Where:** line 327, `! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false`

**Why it is wrong:**
- Suppose `CC_ACTIVATION_INERT_SCOPE=claude` made the hook crash, or it failed for any other reason. The output would be empty or an error message.
- The test would still pass.
- Compare the M3 kill switch (line 208), which also asserts the restored behaviour is present.

### 5. M4 "behind trunk" fixture builds the opposite shape

**What:** The fixture puts the checkout *ahead* of trunk, with a local commit that deletes the file. The test claims to model a checkout *behind* trunk.

**Where:**
- line 234, `# the checkout is BEHIND trunk for this path — the deploy-lag shape`
- lines 235–237, `( cd "$w"; git rm -q docs/activation/pending-activation/landed-activate.sh; git commit -q -m drop` … `git reset -q --hard HEAD~1; git rm -q --cached …` … `rm -f …; git commit -q -m "checkout behind" ) >/dev/null 2>&1`
- line 271, the same shape in the kill-switch test

**Why it is wrong:**
- The drop / `reset --hard HEAD~1` pair cancels out.
- The net result is `HEAD` = `origin/main` + one unpushed commit that removes the file. So the checkout is ahead, and has deliberately deleted a committed file.
- That is not deploy lag, where the checkout trails trunk and a fast-forward would restore the file.
- An adjudicator that only works in the real behind case would not be exercised, for example one that checks whether `HEAD` is an ancestor of `origin/main`.
- For this ahead/deleted shape, the asserted advice "do NOT cp live->repo" (line 244) is being certified for a case it was not designed for.

### 6. M4 negative check is pinned to one exact wording

**What:** The guard against a false "never committed" verdict matches only one exact rendering, so any other wording of the same wrong verdict slips past it.

**Where:** line 242, `! printf '%s' "$output" | grep -q "LIVE-ONLY — never committed, one .rm. from unrecoverable: landed-activate.sh" || false`

**Why it is wrong:**
- Suppose the hook wrongly classifies `landed-activate.sh` as LIVE-ONLY but formats the line differently. Possible differences include:
  - a different dash or separator;
  - several names on one line, so the name does not directly follow the colon;
  - reworded text.
- The negation then passes vacuously.
- By contrast, the matching positive control (line 253) and the kill switch (lines 275–276) use the bare labels `LIVE-ONLY` and `UNDEPLOYED-MIRROR`.
