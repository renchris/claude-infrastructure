I read the file in full. Seven defects found, ordered by severity.

**1. The LIVE-ONLY test and the UNCONFIRMED test use the same mirror shape but assert different verdicts, so at least one of them passes for a reason other than its title, and the M4 positive control cannot tell "absent from trunk" from "trunk unreadable".**

Where:
```
90   M="$BATS_TEST_TMPDIR/mirror"; mkdir -p "$M"
95   printf '%s' "$output" | grep -q 'LIVE-ONLY'
262  mkdir -p "$BATS_TEST_TMPDIR/bare-mirror"
265  printf '%s' "$output" | grep -q 'UNCONFIRMED'
253  printf '%s' "$output" | grep -q 'LIVE-ONLY'
255  ! printf '%s' "$output" | grep -q 'UNDEPLOYED-MIRROR' || false
```
Why: Both line 90 and line 262 give the hook a plain directory with no `.git`, containing no copy of the live file. The `.done` marker on line 263 only silences axis 1, so axis 2 sees identical input in both tests. The M4 comment block says a non-checkout mirror must yield UNCONFIRMED rather than a LIVE-ONLY guess. Both tests can only be green together if the hook prints both tokens for an unreadable trunk. In that case line 95 is satisfied by the UNCONFIRMED path, not by the "never committed" verdict the test claims to prove. It also means the M4 positive control on lines 253 to 255 passes whenever trunk adjudication fails for any reason, because it never excludes UNCONFIRMED. Line 265 likewise never excludes the confident "never committed" wording or the `cp live->repo` instruction that the M4 comment says is wrong to emit.

**2. The axis-2 section says every fixture is `.done`-marked so findings are attributable to parity alone, but three fixtures are not marked, so their filename assertions are satisfied by axis 1.**

Where:
```
84   # Fixtures are `.done`-MARKED throughout, so axis 1 stays silent and every finding below is
91   stage "12-only-live-activate.sh"
94   printf '%s' "$output" | grep -q '12-only-live-activate.sh'
109  printf '#!/bin/bash\n# LIVE\n' > "$Q/07-drift-activate.sh"
112  printf '%s' "$output" | grep -q '07-drift-activate.sh'
134  stage "x-activate.sh"
```
Why: With M3 partitioning, an unmarked fresh file is always named in the FRESH partition. So line 94 and line 112 pass even if the parity axis reports the class token with the wrong filename or no filename at all. The isolation the header promises does not hold for these three tests.

**3. The M4 deploy-lag fixture builds a checkout that is ahead of trunk with a deliberate delete commit, not a checkout behind trunk.**

Where:
```
234  # the checkout is BEHIND trunk for this path — the deploy-lag shape
235  ( cd "$w"; git rm -q docs/activation/pending-activation/landed-activate.sh; git commit -q -m drop
236    git reset -q --hard HEAD~1; git rm -q --cached docs/activation/pending-activation/landed-activate.sh
237    rm -f docs/activation/pending-activation/landed-activate.sh; git commit -q -m "checkout behind" ) >/dev/null 2>&1
```
Why: The "drop" commit is immediately undone by the hard reset, so lines 235 and 236 up to the reset are a no-op. The net state is local main equals base plus one commit that removes the file, while origin/main stays at base. That is a branch one commit ahead of trunk that intentionally deleted the file, which is the opposite of trailing origin. If the adjudicator considers ancestry, this fixture does not exercise the claimed class. If it only checks whether the path exists on origin/main, the test pins UNDEPLOYED-MIRROR and "do NOT cp live->repo" for a shape where the local branch chose to delete the file, which is not deploy lag.

**4. Two negative-only tests have no status check and no positive assertion, so a hook that crashes with empty output passes them.**

Where:
```
307  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
327  ! printf '%s' "$output" | grep -q 'CLAIMED-DONE BUT INERT' || false
```
Why: If the stub is not executable, the hook errors out on an unknown value for the inert-scope variable, or the launchctl-bin override is ignored and the real binary fails, output is empty and the negation passes. A failure is reported as the axis "going quiet" or the kill switch "working".

**5. The two M4 subshells chain `git` commands after a `cd` with no guard, so the only thing preventing a hard reset in the invoking repository is errexit being inherited into the subshell.**

Where:
```
235  ( cd "$w"; git rm -q docs/activation/pending-activation/landed-activate.sh; git commit -q -m drop
236    git reset -q --hard HEAD~1; git rm -q --cached docs/activation/pending-activation/landed-activate.sh
270  ( cd "$w"; git rm -q --cached docs/activation/pending-activation/landed-activate.sh
```
Why: The helper on line 225 uses `cd "$w" || exit 1`, and the helper always returns a path even when the clone failed because its subshell status is discarded and only `printf` runs last. If `$w` does not exist and errexit is not in effect inside the subshell, the commit and `git reset -q --hard HEAD~1` execute in the current directory, which under bats is the repository the tests were launched from. All output is discarded by the redirect, so nothing would show why.

**6. The M3 kill-switch test only checks that the fresh entry is hidden and the old header appears; it never checks that the stale entry is still named.**

Where:
```
208  printf '%s' "$output" | grep -q 'staged >24h and NOT run'
209  ! printf '%s' "$output" | grep -q 'b-new-activate.sh' || false
```
Why: A filter mode that prints the header and then drops every entry passes this test. The title claims the switch restores the old filter "exactly", but the test would accept a filter that names nothing.

**7. The negative assertion in the M4 trunk test matches one exact sentence, so any other LIVE-ONLY wording slips past it.**

Where:
```
242  ! printf '%s' "$output" | grep -q "LIVE-ONLY — never committed, one .rm. from unrecoverable: landed-activate.sh" || false
```
Why: The sibling negatives on lines 255 and 276 use the bare token. If the hook emits both UNDEPLOYED-MIRROR and a LIVE-ONLY line for the same file in any phrasing other than this one, line 240 passes and line 242 passes too, and the test reports the "never 'never committed'" claim as verified when it is not.
