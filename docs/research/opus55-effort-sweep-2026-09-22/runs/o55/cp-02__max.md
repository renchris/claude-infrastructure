Line numbers count `#!/usr/bin/env bats` as line 1. I found 13 defects.

1. **What:** The LIVE-ONLY fixture has no `.done` marker, so the filename assertion passes on axis 1's FRESH row no matter what the parity axis reports.
   **Where:** line 91 `stage "12-only-live-activate.sh"`; line 94 `printf '%s' "$output" | grep -q '12-only-live-activate.sh'`
   **Why:** Since M3, axis 1 names fresh un-run entries (lines 47–51 require this). So the filename is in the output even if axis 2 prints a `LIVE-ONLY` heading with an empty or wrong list. This is the "freshness no longer buys silence" hazard that lines 84–87 say this section avoids by marking every fixture.

2. **What:** The LIVE-ONLY test runs against a plain non-checkout directory, which is the M4 UNCONFIRMED case, so it never establishes the "never committed" verdict in its title.
   **Where:** line 90 `M="$BATS_TEST_TMPDIR/mirror"; mkdir -p "$M"`; line 95 `printf '%s' "$output" | grep -q 'LIVE-ONLY'`
   **Why:** Lines 262–265 use the same mirror shape (a `mkdir`'d directory, no trunk) with a live-only file and require `UNCONFIRMED`, because "guessing either way is wrong". So either this test contradicts M4, or its `LIVE-ONLY` grep is matching text that the UNCONFIRMED path also prints. In the second case it passes on a verdict other than the one it names.

3. **What:** The CONTENT-DRIFT live file has no `.done` marker, so the filename assertion is satisfied by axis 1 rather than by the CONTENT-DRIFT row.
   **Where:** line 109 `printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"`; line 112 `printf '%s' "$output" | grep -q '07-drift-activate.sh'`
   **Why:** The fresh file is named in axis 1's FRESH partition. Line 112 therefore passes even if the CONTENT-DRIFT row names nothing or the wrong file. Only the bare token on line 113 can be attributed to axis 2.

4. **What:** The unresolvable-mirror fixture has no `.done` marker, so axis 1 always emits alongside it and the case where `DID NOT RUN` is the only finding is never exercised.
   **Where:** line 134 `stage "x-activate.sh"`
   **Why:** Suppose the hook only appends `DID NOT RUN` when there is already an emit. That hook passes this test. With an all-`.done` queue and an unresolvable mirror, it would print nothing at all, which is the "silent vacuous pass" the title rules out.

5. **What:** The symlink test's "never ~/.claude" negative cannot fail for the non-dereferenced case it guards, because the fixture symlink is not under a `.claude` directory.
   **Where:** line 145 `ln -s "$H" "$BATS_TEST_TMPDIR/linked.sh"`; line 150 `! printf '%s' "$output" | grep -q '\.claude/docs/activation'`
   **Why:** Without dereferencing, the repo resolves to the parent of `$BATS_TEST_TMPDIR`, not `~/.claude`, so line 150 passes either way. Line 149 is the only check that discriminates. It also passes on the non-dereferenced path whenever the `.git`-gate fallback (the FALLBACK_REPO shared checkout, line 148) is the same checkout the suite is run from.

6. **What:** The M3 kill-switch test never asserts that the stale entry is still named or that the count reverts, so "restores the >24h filter exactly" goes unchecked.
   **Where:** line 208 `printf '%s' "$output" | grep -q 'staged >24h and NOT run'`; line 209 `! printf '%s' "$output" | grep -q 'b-new-activate.sh' || false`
   **Why:** Two broken switches would pass both lines:
   - one that prints the old header but drops `a-old-activate.sh`;
   - one that keeps M3's whole-queue count, printing "2 … staged >24h and NOT run" when only one entry is stale.

7. **What:** `mkmirror` discards every failure while building the git fixture and prints the path unconditionally, so a broken fixture is reported as a good one.
   **Where:** line 224 `git init -q --bare "$o"; git clone -q "$o" "$w" 2>/dev/null`; line 228 `git add -A; git commit -q -m base; git push -q -u origin main ) >/dev/null 2>&1`; line 229 `printf '%s' "$w"`
   **Why:** It runs inside `w="$(mkmirror …)"`, where bash clears errexit unless `inherit_errexit` is set. The subshell's status is never checked and its output goes to `/dev/null`. If `git commit` is refused (for example by a global `commit.gpgsign=true` or a global hooks path), no `origin/main` exists. `mkmirror` still returns 0 and the M4 tests carry on. The positive control (lines 253–255) then passes on the UNCONFIRMED path (see 9) with no trunk at all.

8. **What:** The fixture labelled "the checkout is BEHIND trunk" actually leaves the checkout one commit ahead of `origin/main`, through a local commit that deletes the file.
   **Where:** lines 234–237
   ```
   # the checkout is BEHIND trunk for this path — the deploy-lag shape
   ( cd "$w"; git rm -q docs/activation/pending-activation/landed-activate.sh; git commit -q -m drop
     git reset -q --hard HEAD~1; git rm -q --cached docs/activation/pending-activation/landed-activate.sh
     rm -f docs/activation/pending-activation/landed-activate.sh; git commit -q -m "checkout behind" ) >/dev/null 2>&1
   ```
   **Why:** `reset --hard HEAD~1` discards `drop`. The net history is base → "checkout behind" (a deletion), while `origin/main` stays at base: 1 ahead, 0 behind. Trunk has no commit the checkout lacks.
   - The M4 header's deploy-lag state (the checkout trails `origin/main` and the next fast-forward brings the file back) is never built.
   - In the state that is built, no fast-forward restores the file, and a push would delete it from trunk.
   - Yet the test pins the deploy-lag verdict and its "do NOT cp live->repo" advice. It passes for any adjudicator that just looks the path up in `origin/main`, and says nothing about a lagging checkout.

9. **What:** No test positively asserts the confirmed "never committed" LIVE-ONLY verdict: the M4 positive control greps only the bare `LIVE-ONLY` token, and the full phrase appears only inside a negative.
   **Where:** line 253 `printf '%s' "$output" | grep -q 'LIVE-ONLY'`; line 242 `! printf '%s' "$output" | grep -q "LIVE-ONLY — never committed, one .rm. from unrecoverable: landed-activate.sh" || false`
   **Why:** Line 95 (plain-dir mirror) and line 265 (same shape, UNCONFIRMED) can only both pass if the UNCONFIRMED output also contains `LIVE-ONLY`. That has two consequences:
   - An adjudicator that files every trunk-absent path as UNCONFIRMED (treating "not in `origin/main`" like "trunk unreadable") passes lines 253–255. So does a trunk that `mkmirror` failed to create. The "one `rm` from unrecoverable" alarm, which lines 248–249 say this control protects, can be downgraded while the whole file stays green.
   - Line 242's exact phrase is never shown to match real output, so any rewording of that row makes the negative vacuous.

10. **What:** The UNCONFIRMED test asserts only that the word appears, not that `orphan-activate.sh` is reported or that neither guessed verdict is emitted.
    **Where:** line 265 `printf '%s' "$output" | grep -q 'UNCONFIRMED'`
    **Why:** Two wrong outputs pass:
    - an UNCONFIRMED banner with the orphan's row dropped, which is the "silent pass" in the title;
    - UNCONFIRMED printed next to a guessed `UNDEPLOYED-MIRROR` or "never committed … cp live -> repo" row, which are the two outcomes lines 259–261 call wrong.

11. **What:** The M5 positive control only asserts that no INERT row appears, with no status or empty-output check, so it passes when the hook fails.
    **Where:** line 307 `! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false`
    **Why:** If the hook crashes or exits early on the loaded-label path, no INERT row is printed and the test passes. It cannot tell "the axis ran and went quiet" from "the axis never ran". The file's other positive controls (lines 129–130, 200–201) do assert status 0 and empty output.

12. **What:** The DISABLED/NOT-LOADED test checks each tag in its own run but never checks that the other tag is absent, so "distinguished" is not actually tested.
    **Where:** line 317 `printf '%s' "$output" | grep -q 'com.claude.log-rotation \[DISABLED\]'`; line 319 `printf '%s' "$output" | grep -q 'com.claude.log-rotation \[NOT-LOADED\]'`
    **Why:** A hook that tags the disabled label both `[DISABLED]` and `[NOT-LOADED]` passes, for example if the old `launchctl list`-only row still fires. That output still sends the operator to `bootstrap`, which is the regression lines 311–312 describe.

13. **What:** The M5 kill-switch test only checks that the com.chrisren row is gone; it never shows that the com.claude-only scope is in force or that the hook succeeded.
    **Where:** lines 325–327
    ```
    CC_ACTIVATION_DIR="$Q" CC_ACTIVATION_INERT_SCOPE=claude \
      CC_ACTIVATION_LAUNCHCTL_BIN="$(lcstub '' '')" run "$H"
    ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
    ```
    **Why:** A switch that turns axis 3 off entirely, or makes the hook crash, produces no INERT row and passes. No com.claude label is staged that should still fire under `scope=claude`, and there is no status check. By contrast, the M3 and M4 kill-switch tests both assert positive output.

Not reported: the `!` assertions without `|| false` (lines 23, 80, 150) are each the last command in their test, so they do fail the test when they should.
